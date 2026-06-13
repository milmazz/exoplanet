# Split Fetcher / Pure Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `Exoplanet.Fetcher` (HTTP + `Exoplanet.Cache`) out of `Exoplanet.Parser`, leaving the parser a pure `body -> [Post]` function.

**Architecture:** Job (1) HTTP/conditional-GET/cache moves to a new `Exoplanet.Fetcher.fetch/2`. `Exoplanet.Parser.parse/3` becomes pure (`parse(body, url, name)`, binary-only). `Exoplanet.build_source/3` orchestrates fetch→parse, guarding the `nil` (fetch-failed) case. Behavior is preserved; the existing suite is the regression net, repointed at the new `Exoplanet.Fetcher` stub key. A new no-stub `parser_test.exs` is the coverage the split unlocks.

**Tech Stack:** Elixir, ExUnit, `Req` / `Req.Test`, `fast_rss` (NIF), `lazy_html`.

**Spec:** `docs/superpowers/specs/2026-06-13-split-fetcher-parser-design.md`

---

## File Structure

- **Create** `lib/exoplanet/fetcher.ex` — HTTP + `Exoplanet.Cache` interaction. Public `fetch/2`.
- **Modify** `lib/exoplanet/parser.ex` — strip HTTP/cache; new pure `parse/3`.
- **Modify** `lib/exoplanet.ex` — `build_source/3` calls `Fetcher.fetch` then `Parser.parse`, handling `nil`.
- **Modify** `test/test_helper.exs` — stub plug name → `Exoplanet.Fetcher`.
- **Modify** `test/support/test_helpers.ex` — stub key + docs → `Exoplanet.Fetcher`.
- **Modify** `test/exoplanet_test.exs` — stub key → `Exoplanet.Fetcher`.
- **Rename** `test/exoplanet/parser_cache_test.exs` → `test/exoplanet/fetcher_cache_test.exs` — module + stub keys → Fetcher.
- **Modify** `test/exoplanet/req_options_test.exs` — persistent_term key → `Exoplanet.Fetcher`.
- **Create** `test/exoplanet/parser_test.exs` — pure parser tests, no stubs.
- **Modify** `CLAUDE.md` — Architecture bullets.

---

## Task 1: Extract `Exoplanet.Fetcher` (coordinated refactor, suite stays green)

This is an atomic refactor: the module move, the `parse/3` signature change, the orchestrator rewire, and the stub-key rename must land together or the suite won't compile. The existing test suite is the regression net — it must be green at the end of this task.

**Files:**
- Create: `lib/exoplanet/fetcher.ex`
- Modify: `lib/exoplanet/parser.ex` (replace lines 1-178; keep line 180+ `rss_body?/1` onward)
- Modify: `lib/exoplanet.ex` (`build_source/3`, lines 64-76)
- Modify: `test/test_helper.exs`
- Modify: `test/support/test_helpers.ex`
- Modify: `test/exoplanet_test.exs`
- Rename + modify: `test/exoplanet/parser_cache_test.exs` → `test/exoplanet/fetcher_cache_test.exs`
- Modify: `test/exoplanet/req_options_test.exs`

- [ ] **Step 1: Create `lib/exoplanet/fetcher.ex`**

This is the HTTP/cache code moved verbatim from `parser.ex` (current lines 20-178), with `fetch_body/2` renamed to the public `fetch/2` and the persistent_term latch key rebased to `__MODULE__` (now `Exoplanet.Fetcher`).

```elixir
defmodule Exoplanet.Fetcher do
  @moduledoc false
  require Logger

  # Fetches the feed body, using the configured cache adapter for conditional
  # GET when available. Returns the body string, or nil on an uncached error.
  def fetch(url, config) do
    {conditional_headers, cached_entry} = build_conditional_headers(url)

    # Retries are off by default: with the feed_timeout task backstop in
    # `Exoplanet.build/1` a retried request could never finish anyway, and a
    # prompt error return is what lets us fall back to the cached body.
    # Consumers can re-enable retries via the :req_options app env key.
    opts =
      [receive_timeout: to_timeout(second: config.feed_timeout), retry: false]
      |> Keyword.merge(req_options())
      |> merge_headers(conditional_headers)

    case Req.get(url, opts) do
      {:ok, %{status: 304}} ->
        Logger.debug("Feed #{url}: 304 Not Modified, using cached body")
        maybe_notify_success(url, 304)
        cached_entry && cached_entry.body

      {:ok, %{status: 200, body: body} = resp} ->
        # maybe_update_cache stores etag/body; maybe_notify_success resets error state.
        # Both write to the feeds table on cacheable responses — intentional trade-off.
        maybe_update_cache(url, resp, body)
        maybe_notify_success(url, 200)
        body

      {:ok, %{status: status}} ->
        Logger.error("Feed #{url}: unexpected HTTP status #{status}")
        maybe_notify_error(url, status, "HTTP #{status}")
        cached_entry && cached_entry.body

      {:error, reason} ->
        Logger.error(
          "something went wrong while retrieving URL: #{url}, reason: #{inspect(reason)}"
        )

        maybe_notify_error(url, nil, inspect(reason))

        # Fall back to cached body (if any) so a transient error doesn't blank
        # out content we already have.
        cached_entry && cached_entry.body
    end
  end

  # Extra options forwarded to `Req.get/2` (user-agent, proxy, retry policy,
  # test plugs, ...). `:planet_req_options` is the deprecated pre-0.6 name,
  # kept as a fallback for existing consumers.
  defp req_options do
    case Application.get_env(:exoplanet, :req_options) do
      nil ->
        case Application.get_env(:exoplanet, :planet_req_options) do
          nil ->
            []

          legacy ->
            warn_legacy_req_options()
            legacy
        end

      opts ->
        opts
    end
  end

  # Warn once per VM, not once per feed fetch — a planet rebuild touches
  # every source and would otherwise repeat this for each of them.
  defp warn_legacy_req_options do
    unless :persistent_term.get({__MODULE__, :legacy_req_options_warned}, false) do
      :persistent_term.put({__MODULE__, :legacy_req_options_warned}, true)

      Logger.warning(
        "the :planet_req_options application env key is deprecated; " <>
          "rename it to :req_options (config :exoplanet, req_options: [...])"
      )
    end
  end

  defp cache_adapter, do: Application.get_env(:exoplanet, :cache_adapter)

  defp maybe_notify_success(url, status), do: maybe_call_adapter(:on_success, [url, status])

  defp maybe_notify_error(url, status, reason),
    do: maybe_call_adapter(:on_error, [url, status, reason])

  defp maybe_call_adapter(callback, args) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        # `function_exported?/3` returns false for modules that haven't been
        # loaded yet (e.g. in dev/interactive mode), so ensure the adapter is
        # loaded before probing for the optional callback.
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, callback, length(args)) do
          apply(adapter, callback, args)
        end

        :ok
    end
  end

  defp build_conditional_headers(url) do
    case cache_adapter() do
      nil ->
        {[], nil}

      adapter ->
        case adapter.get(url) do
          %{etag: etag, last_modified: last_modified} = entry ->
            headers =
              []
              |> prepend_if(etag, {"if-none-match", etag})
              |> prepend_if(last_modified, {"if-modified-since", last_modified})

            {headers, entry}

          nil ->
            {[], nil}
        end
    end
  end

  defp maybe_update_cache(url, resp, body) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        etag = get_response_header(resp, "etag")
        last_modified = get_response_header(resp, "last-modified")

        if etag || last_modified do
          adapter.put(url, %{etag: etag, last_modified: last_modified, body: body})
        end

        :ok
    end
  end

  # Req 0.5 stores response headers as %{String.t() => [String.t()]}
  defp get_response_header(%{headers: headers}, name) do
    case Map.get(headers, name, []) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp merge_headers(opts, []), do: opts

  defp merge_headers(opts, extra_headers) do
    Keyword.update(opts, :headers, extra_headers, fn existing ->
      existing ++ extra_headers
    end)
  end

  defp prepend_if(list, condition, item) do
    if condition, do: [item | list], else: list
  end
end
```

- [ ] **Step 2: Rewrite the top of `lib/exoplanet/parser.ex`**

Replace the current lines 1-178 (the `defmodule`/`@moduledoc`/`require` header, `parse/2`, `fetch_body/2`, and every HTTP/cache helper down through `prepend_if/3`) with the header below. **Keep everything from the current line 180 (`# RSS 2.0 uses <rss ...>` / `defp rss_body?`) to the end of the file unchanged.**

New file header (replaces lines 1-178):

```elixir
defmodule Exoplanet.Parser do
  @moduledoc false
  require Logger

  # Pure feed parser: turns a fetched feed body into built `%Exoplanet.Post{}`
  # structs. HTTP and cache interaction live in `Exoplanet.Fetcher`; the
  # orchestrator (`Exoplanet.build_source/3`) fetches first and only calls this
  # with a real binary body.
  def parse(body, url, name) when is_binary(body) do
    raw_items =
      if rss_body?(body),
        do: parse_rss(url, body, name),
        else: parse_atom(url, body, name)

    Enum.map(raw_items, fn {attrs, content} -> Exoplanet.Post.build(attrs, content) end)
  end
```

Verify after editing that the next line in the file is the existing `# RSS 2.0 uses <rss ...>` comment immediately followed by `defp rss_body?(body) do`.

- [ ] **Step 3: Rewire `Exoplanet.build_source/3` in `lib/exoplanet.ex`**

Replace the current `build_source/3` (lines 63-76) with:

```elixir
  # Fetch, parse, filter, and cap a single source.
  defp build_source({url, attrs}, defaults, config) do
    filters = Exoplanet.Filters.merge(defaults, attrs[:filters])

    case Exoplanet.Fetcher.fetch(url, config) do
      nil ->
        []

      body ->
        body
        |> Exoplanet.Parser.parse(url, attrs.name)
        |> Exoplanet.Filters.apply(filters)
        # Sort each per-feed list by publication date (descending) before
        # capping with `new_feed_items`. Some feeds don't emit entries in
        # newest-first order; without this sort, document-order older
        # entries can crowd out the genuinely-recent ones.
        |> sort_by_published_desc()
        |> Enum.take(config.new_feed_items)
    end
  end
```

- [ ] **Step 4: Repoint the `Req.Test` stub key in `test/test_helper.exs`**

Change the plug name from `Exoplanet.Parser` to `Exoplanet.Fetcher`:

```elixir
Application.put_env(:exoplanet, :req_options,
  plug: {Req.Test, Exoplanet.Fetcher},
  retry: false
)

ExUnit.start()
```

- [ ] **Step 5: Repoint stub key + docs in `test/support/test_helpers.ex`**

Replace the two doc strings and the two `Req.Test.stub(Exoplanet.Parser, ...)` calls with `Exoplanet.Fetcher`:

```elixir
  @doc "Stub `Exoplanet.Fetcher` to return the given fixture for every request."
  def stub_feed(name) when is_atom(name) do
    body = fixture(name)
    Req.Test.stub(Exoplanet.Fetcher, fn conn -> Req.Test.html(conn, body) end)
  end

  @doc """
  Stub `Exoplanet.Fetcher` to dispatch by `conn.host` to a fixture name.
  Useful for multi-source tests (e.g. ordering across feeds).
  """
  def stub_feeds(routes) when is_map(routes) do
    bodies = Map.new(routes, fn {host, name} -> {host, fixture(name)} end)

    Req.Test.stub(Exoplanet.Fetcher, fn conn ->
      Req.Test.html(conn, Map.fetch!(bodies, conn.host))
    end)
  end
```

- [ ] **Step 6: Repoint stub keys in `test/exoplanet_test.exs`**

There are 11 occurrences of `Req.Test.stub(Exoplanet.Parser` in this file. Replace all of them with `Req.Test.stub(Exoplanet.Fetcher`. (Editor: replace-all on the string `Req.Test.stub(Exoplanet.Parser` → `Req.Test.stub(Exoplanet.Fetcher`.)

Run to confirm none remain:

```bash
grep -c "Req.Test.stub(Exoplanet.Parser" test/exoplanet_test.exs
```
Expected: `0`

- [ ] **Step 7: Rename and repoint the cache test file**

```bash
git mv test/exoplanet/parser_cache_test.exs test/exoplanet/fetcher_cache_test.exs
```

In `test/exoplanet/fetcher_cache_test.exs`:
- Rename the module `Exoplanet.ParserCacheTest` → `Exoplanet.FetcherCacheTest` (line 1).
- Replace all `Req.Test.stub(Exoplanet.Parser` → `Req.Test.stub(Exoplanet.Fetcher` (6 occurrences).

Run to confirm:

```bash
grep -c "Req.Test.stub(Exoplanet.Parser" test/exoplanet/fetcher_cache_test.exs
```
Expected: `0`

- [ ] **Step 8: Repoint persistent_term key in `test/exoplanet/req_options_test.exs`**

Change the `on_exit` cleanup key from `Exoplanet.Parser` to `Exoplanet.Fetcher`:

```elixir
      :persistent_term.erase({Exoplanet.Fetcher, :legacy_req_options_warned})
```

- [ ] **Step 9: Run the full suite — must be green**

Run: `mix test`
Expected: PASS — all existing tests pass (0 failures). This confirms behavior is preserved across the extraction. If `fast_rss` NIF errors appear, run `mix deps.compile --force` first, then re-run.

- [ ] **Step 10: Verify formatting + compile warnings**

Run: `mix format --check-formatted && mix compile --warnings-as-errors`
Expected: no output / exit 0. (Confirms `parser.ex` has no unused-`Req`/orphan-function warnings after the strip.)

- [ ] **Step 11: Commit**

```bash
git add lib/exoplanet/fetcher.ex lib/exoplanet/parser.ex lib/exoplanet.ex \
  test/test_helper.exs test/support/test_helpers.ex test/exoplanet_test.exs \
  test/exoplanet/fetcher_cache_test.exs test/exoplanet/req_options_test.exs
git commit -m "refactor: extract Exoplanet.Fetcher; make Parser pure (body -> [Post])

HTTP + Exoplanet.Cache interaction moves to Exoplanet.Fetcher.fetch/2.
Exoplanet.Parser.parse/3 is now pure. build_source orchestrates and
guards the nil fetch-failure case. Req.Test stub key renamed to
Exoplanet.Fetcher; parser_cache_test renamed to fetcher_cache_test.

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: New pure parser tests (`parser_test.exs`)

The coverage the split unlocks: exercise `Parser.parse/3` directly against fixture bodies with **no `Req.Test` stub**.

**Files:**
- Create: `test/exoplanet/parser_test.exs`

- [ ] **Step 1: Write the pure parser test file**

```elixir
defmodule Exoplanet.ParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Exoplanet.TestHelpers

  alias Exoplanet.Parser
  alias Exoplanet.Post

  @url "https://example.test/feed"
  @name "Source Name"

  describe "parse/3 with RSS bodies (no HTTP stub)" do
    test "parses an RSS 2.0 feed into Post structs" do
      posts = Parser.parse(fixture(:rss), @url, @name)

      assert [%Post{} | _] = posts
      assert Enum.all?(posts, &(&1.feed_url == @url))
      assert Enum.all?(posts, &match?(%NaiveDateTime{}, &1.published))
    end

    test "parses RSS 1.0 (rdf:RDF) bodies" do
      assert [%Post{} | _] = Parser.parse(fixture(:rss1), @url, @name)
    end

    test "parses RSS without a version attribute" do
      assert [%Post{} | _] = Parser.parse(fixture(:rss_no_version), @url, @name)
    end

    test "prefers <content:encoded> over <description>" do
      [post | _] = Parser.parse(fixture(:rss_with_content_encoded), @url, @name)
      # content:encoded fixture carries the full HTML article body.
      assert post.body =~ "content:encoded"
    end

    test "falls back to the source name when <author> is blank" do
      body = """
      <rss version="2.0"><channel>
        <title>T</title><link>https://example.test</link>
        <item>
          <title>P</title><link>https://example.test/p</link>
          <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
          <author>   </author><description>Body</description>
        </item>
      </channel></rss>
      """

      assert [%Post{authors: [@name]}] = Parser.parse(body, @url, @name)
    end

    test "skips an entry with an unparseable date and logs a warning" do
      log =
        capture_log(fn ->
          assert [] == Parser.parse(fixture(:rss_bad_date), @url, @name)
        end)

      assert log =~ "unparseable"
    end
  end

  describe "parse/3 with Atom bodies (no HTTP stub)" do
    test "parses an Atom feed into Post structs" do
      posts = Parser.parse(fixture(:atom), @url, @name)

      assert [%Post{} | _] = posts
      assert Enum.all?(posts, &(&1.feed_url == @url))
    end

    test "skips entries missing both <published> and <updated>" do
      # Fixture has at least one dateless entry that must be dropped.
      posts = Parser.parse(fixture(:atom_published_missing), @url, @name)
      assert Enum.all?(posts, &match?(%NaiveDateTime{}, &1.published))
    end

    test "cleans trailing-comma categories" do
      [post | _] = Parser.parse(fixture(:atom_with_trailing_comma_categories), @url, @name)
      refute Enum.any?(post.categories || [], &String.ends_with?(&1, ","))
    end
  end
end
```

- [ ] **Step 2: Run the new tests**

Run: `mix test test/exoplanet/parser_test.exs`
Expected: PASS. These are characterization tests against the now-pure API; they confirm `parse/3` works with a plain binary and no `Req.Test` stub. If `parse/3` were still impure (e.g. tried to fetch), they would crash — so green here proves the purity goal.

Note: if any assertion about specific fixture content (e.g. the `=~ "content:encoded"` body check or the trailing-comma category fixture) fails because the fixture's actual content differs, open the fixture (`test/support/fixtures/feeds/<name>.xml`) and adjust the assertion to match the real content rather than weakening it to a tautology.

- [ ] **Step 3: Run the full suite**

Run: `mix test`
Expected: PASS (0 failures).

- [ ] **Step 4: Commit**

```bash
git add test/exoplanet/parser_test.exs
git commit -m "test: pure Exoplanet.Parser tests with no Req.Test stub

Exercise parse/3 directly against fixture bodies, demonstrating the
parser is now a pure body -> [Post] function.

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Update architecture docs in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (Architecture section)

- [ ] **Step 1: Verify the modules referenced in the new docs exist**

Run:
```bash
ls lib/exoplanet/fetcher.ex lib/exoplanet/parser.ex
grep -n "def fetch" lib/exoplanet/fetcher.ex
grep -n "def parse" lib/exoplanet/parser.ex
```
Expected: both files listed; `def fetch(url, config)` and `def parse(body, url, name)` present. (Per CLAUDE.md's Documentation Edits rule: verify references before editing docs.)

- [ ] **Step 2: Replace the `Exoplanet.Parser` architecture bullet**

In `CLAUDE.md`, find the bullet beginning `- \`Exoplanet.Parser\` — purely HTTP fetch + XML parse.` and replace that single bullet with these two bullets (keep all surrounding bullets intact):

```markdown
- `Exoplanet.Fetcher` — HTTP fetch + `Exoplanet.Cache` interaction only. `fetch(url, config)` returns the body string or `nil` on an uncached error. HTTP requests use `feed_timeout` as Req's `:receive_timeout`; extra Req options come from the `:req_options` application env key (`:planet_req_options` is the deprecated fallback). When a cache adapter is present it adds `If-None-Match`/`If-Modified-Since` headers and falls back to the cached body on non-200 responses or network errors.
- `Exoplanet.Parser` — pure `parse(body, url, name) -> [Post]`. No HTTP; `Exoplanet.build_source/3` fetches first and only calls `parse/3` with a real binary body. Detects RSS vs Atom via `rss_body?/1`: RSS if the body contains `<rss` or `<rdf:RDF` (covers RSS 2.0, RSS without version attribute, and RSS 1.0); otherwise treats as Atom. RSS bodies prefer `<content:encoded>` (Content RSS module) over `<description>` so Medium-style feeds render correctly. RSS dates use the custom `DateTimeParser`; Atom dates use `NaiveDateTime.from_iso8601/1`. An entry without a usable date is skipped (RSS without `<pubDate>`, Atom without either `<published>` or `<updated>`); an unparseable date additionally logs a warning. In both cases sibling posts in the same feed are still parsed. Blank authors/summaries are normalised to fall back to the source's `name` and `nil` respectively.
```

- [ ] **Step 3: Update the `Exoplanet.build/1` bullet's parenthetical (if present)**

In the `Exoplanet.build/1` bullet, the phrase `receive_timeout` in `Exoplanet.Parser` no longer holds. If the bullet references the parser for the HTTP timeout, update that reference to `Exoplanet.Fetcher`. Verify first:

```bash
grep -n "receive_timeout\|Exoplanet.Parser" CLAUDE.md
```
Then update any HTTP-timeout reference from `Exoplanet.Parser` to `Exoplanet.Fetcher`. Leave references that are genuinely about parsing alone.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md architecture for Fetcher/Parser split

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS (compile, format, deps.unlock, docs, test all clean). If `mix precommit` is unavailable, run `mix compile --warnings-as-errors && mix format --check-formatted && mix test`.

- [ ] **Step 2: Confirm the stub-key rename is complete**

Run: `grep -rn "Req.Test.stub(Exoplanet.Parser\|{Exoplanet.Parser, :legacy" test/`
Expected: no output (all references now point at `Exoplanet.Fetcher`).

- [ ] **Step 3: Confirm `parser.ex` no longer touches HTTP**

Run: `grep -n "Req\.\|fetch_body\|cache_adapter\|req_options" lib/exoplanet/parser.ex`
Expected: no output (all HTTP/cache code now lives in `fetcher.ex`).

---

## Self-Review Notes

- **Spec coverage:** Fetcher module (Task 1.1), pure Parser (Task 1.2), orchestrator nil-guard (Task 1.3), stub-key rename (Task 1.4-1.8), cache test rename (Task 1.7), req_options key (Task 1.8), new pure parser tests (Task 2), CLAUDE.md docs (Task 3) — all spec sections mapped.
- **Behavior preservation:** Task 1 ends green on the existing suite (the regression net); Task 2 adds new coverage; Task 4 re-verifies end-to-end.
- **No public-API change:** `Exoplanet.build/1` untouched — no README edit needed.

# Sanitizer Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional `Exoplanet.Sanitizer` behaviour so consumers can delegate HTML sanitization to a comprehensive library (e.g. `html_sanitize_ex`); when configured it replaces the built-in sanitizer.

**Architecture:** A public behaviour `Exoplanet.Sanitizer` with one callback `sanitize(html) -> html`. `Exoplanet.Filters` reads a `:sanitizer_adapter` application-env module (per call, like `Exoplanet.Fetcher` reads `:cache_adapter`) and, when `sanitize_html: true` and an adapter is set, runs the adapter instead of the built-in tree-walk. `strip_images`/`excerpt` are unchanged and run after. No new runtime dependency; `html_sanitize_ex` is documented as the example adapter and tests use inline fakes.

**Tech Stack:** Elixir, ExUnit, `LazyHTML` (existing HTML manipulation in Filters).

**Spec:** `.claude/specs/2026-06-13-sanitizer-adapter-design.md`

---

## File Structure

- **Create** `lib/exoplanet/sanitizer.ex` — `Exoplanet.Sanitizer` behaviour (public `@moduledoc`, one `@callback sanitize/1`).
- **Modify** `lib/exoplanet/filters.ex` — `apply_html_filters/2` gains an adapter branch + `sanitizer_adapter/0` and `run_adapter/2` helpers; moduledoc note.
- **Create** `test/exoplanet/filters_sanitizer_test.exs` — adapter behavior tests with inline fakes (`async: false`).
- **Modify** `README.md` — "Stronger sanitization" content in the existing sanitization note.
- **Modify** `CHANGELOG.md` — unreleased `### Added` entry.
- **Modify** `CLAUDE.md` — Architecture bullet for `Exoplanet.Sanitizer` + Filters note.

---

## Task 1: `Exoplanet.Sanitizer` behaviour

**Files:**
- Create: `lib/exoplanet/sanitizer.ex`

- [ ] **Step 1: Write the behaviour module**

```elixir
defmodule Exoplanet.Sanitizer do
  @moduledoc """
  Behaviour for delegating feed-content HTML sanitization to an external
  library.

  `Exoplanet.Filters` ships a built-in sanitizer (`sanitize_html: true`, the
  default) that is defense-in-depth, not a guarantee. For security-sensitive
  rendering you can delegate to a comprehensive sanitizer by implementing this
  behaviour and configuring it:

      config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer

  When an adapter is configured **and** `sanitize_html` is `true`, the adapter
  **replaces** the built-in sanitizer — it is the single authority for what
  HTML is allowed. The built-in `drop_tags`/`drop_attrs`/scheme-allowlist walk
  does not run. The `strip_images` and `excerpt_length` filters are content
  shaping (not sanitization) and still run, after the adapter. Setting
  `sanitize_html: false` disables sanitization entirely and the adapter is not
  called.

  Set `:sanitizer_adapter` to `nil` (or omit it) to use the built-in sanitizer.

  ## Example adapter

  `html_sanitize_ex` is not a dependency of Exoplanet; add it to your own
  application and wrap it:

      defmodule MyApp.FeedSanitizer do
        @behaviour Exoplanet.Sanitizer

        @impl true
        def sanitize(html), do: HtmlSanitizeEx.basic_html(html)
      end

  The callback is invoked once per HTML field (a post's `body` and `summary`)
  with a binary and must return a binary. It is not called for `nil` or empty
  fields.
  """

  @doc """
  Sanitizes one HTML fragment (a post's `body` or `summary`) and returns the
  cleaned HTML.
  """
  @callback sanitize(html :: String.t()) :: String.t()
end
```

- [ ] **Step 2: Compile**

Run: `mix compile --warnings-as-errors`
Expected: exit 0, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/exoplanet/sanitizer.ex
git commit -m "feat: add Exoplanet.Sanitizer behaviour

Optional adapter for delegating HTML sanitization to a comprehensive
library (e.g. html_sanitize_ex). Activated via the :sanitizer_adapter
application env key.

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Wire the adapter into `Exoplanet.Filters`

The current `apply_html_filters/2` (lib/exoplanet/filters.ex:152-184) is a `cond` with three branches: `sanitize?` (fused sanitize + optional strip), `strip_images?` (strip only), and `true` (no-op). We add a new highest-priority branch for "sanitize and an adapter is configured", plus two private helpers. The existing branches stay byte-for-byte.

**Files:**
- Modify: `lib/exoplanet/filters.ex`
- Test: `test/exoplanet/filters_sanitizer_test.exs` (created in Task 3; this task is verified via Task 3's tests, but do TDD by writing the first test here)

- [ ] **Step 1: Write a failing test for the replace behavior**

Create `test/exoplanet/filters_sanitizer_test.exs` with this first test (more tests added in Task 3):

```elixir
defmodule Exoplanet.FiltersSanitizerTest do
  use ExUnit.Case, async: false

  alias Exoplanet.Filters

  # Adapter that returns its input verbatim — proves the built-in walk is
  # BYPASSED (an <iframe>, which the built-in drops, must survive).
  defmodule PassthroughSanitizer do
    @behaviour Exoplanet.Sanitizer
    @impl true
    def sanitize(html), do: html
  end

  defp post(attrs) do
    struct(
      Exoplanet.Post,
      Map.merge(%{body: nil, summary: nil, categories: nil, published: nil}, attrs)
    )
  end

  defp filters(overrides \\ %{}) do
    Map.merge(Exoplanet.Filters.defaults(), overrides)
  end

  setup do
    on_exit(fn -> Application.delete_env(:exoplanet, :sanitizer_adapter) end)
    :ok
  end

  test "a configured adapter replaces the built-in sanitizer" do
    Application.put_env(:exoplanet, :sanitizer_adapter, PassthroughSanitizer)

    html = ~s(<p>hi</p><iframe src="https://e/x"></iframe>)
    [out] = Filters.apply([post(%{body: html})], filters())

    # Built-in would drop <iframe>; the passthrough adapter keeps it, proving
    # the built-in walk did not run.
    assert out.body =~ "<iframe"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/exoplanet/filters_sanitizer_test.exs`
Expected: FAIL — the built-in sanitizer still runs and strips `<iframe>`, so `out.body` does not contain `<iframe`.

- [ ] **Step 3: Add the `sanitizer_adapter/0` helper**

In `lib/exoplanet/filters.ex`, immediately after `defp apply_html_filters(post, filters) do` opening — actually add the helper near the other config readers. Add this private function (place it just before `defp apply_html_filters`):

```elixir
  # Optional sanitizer adapter (an `Exoplanet.Sanitizer` implementation). Read
  # per call, mirroring how `Exoplanet.Fetcher` reads `:cache_adapter`.
  defp sanitizer_adapter, do: Application.get_env(:exoplanet, :sanitizer_adapter)
```

- [ ] **Step 4: Add the adapter branch to `apply_html_filters/2`**

Replace the current `apply_html_filters/2` head and `cond` (lib/exoplanet/filters.ex:152-184). The two existing branches (`sanitize? ->` and `strip_images? ->`) and the `true ->` branch keep their exact current bodies; only a new first branch and the `adapter`/`sanitize?`/`strip_images?` bindings are added.

```elixir
  # Single tree walk that fuses sanitization and image stripping. Returns the
  # post unchanged when neither filter is enabled (no parse/serialize cost).
  #
  # When a `:sanitizer_adapter` is configured and `sanitize_html` is true, the
  # adapter replaces the built-in sanitize walk; `strip_images` then runs after,
  # via the existing strip-only walk.
  defp apply_html_filters(post, filters) do
    sanitize? = Map.get(filters, :sanitize_html, true)
    strip_images? = Map.get(filters, :strip_images, false)
    adapter = sanitizer_adapter()

    cond do
      sanitize? and adapter ->
        post
        |> run_adapter(adapter)
        |> strip_images_only(strip_images?)

      sanitize? ->
        opts = %{
          sanitize?: true,
          drop_tags: MapSet.new(filters.drop_tags),
          # Downcased so user-supplied names like "Style" match the
          # (already-lowercased) attribute names compared in drop_attr?/2.
          drop_attrs: MapSet.new(filters.drop_attrs, &String.downcase/1),
          strip_images?: strip_images?
        }

        transform_html_fields(post, &walk_node(&1, opts), fn _ -> true end)

      strip_images? ->
        opts = %{
          sanitize?: false,
          drop_tags: MapSet.new(),
          drop_attrs: MapSet.new(),
          strip_images?: true
        }

        # Short-circuit when html has no <img>: parse/serialize would otherwise
        # rewrite e.g. `&` → `&amp;` and `<br>` → `<br/>`, breaking byte equality.
        transform_html_fields(post, &walk_node(&1, opts), &has_img?/1)

      true ->
        post
    end
  end

  # Delegate sanitization of :body and :summary to the configured adapter.
  # The adapter is not invoked on nil/empty fields.
  defp run_adapter(post, adapter) do
    post
    |> Map.update!(:body, &adapter_sanitize(adapter, &1))
    |> Map.update!(:summary, &adapter_sanitize(adapter, &1))
  end

  defp adapter_sanitize(_adapter, nil), do: nil
  defp adapter_sanitize(_adapter, ""), do: ""
  defp adapter_sanitize(adapter, html) when is_binary(html), do: adapter.sanitize(html)

  # Image-stripping pass applied after an adapter has sanitized. Runs the
  # existing strip-only walk (no built-in scheme re-check — the adapter is the
  # sanitization authority for this content). No-op when strip_images is off.
  defp strip_images_only(post, false), do: post

  defp strip_images_only(post, true) do
    opts = %{
      sanitize?: false,
      drop_tags: MapSet.new(),
      drop_attrs: MapSet.new(),
      strip_images?: true
    }

    transform_html_fields(post, &walk_node(&1, opts), &has_img?/1)
  end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `mix test test/exoplanet/filters_sanitizer_test.exs`
Expected: PASS.

- [ ] **Step 6: Run the full suite + compile**

Run: `mix test && mix compile --warnings-as-errors && mix format --check-formatted`
Expected: all pass, 0 failures, no warnings. (If `mix format --check-formatted` fails, run `mix format` and re-run.)

- [ ] **Step 7: Commit**

```bash
git add lib/exoplanet/filters.ex test/exoplanet/filters_sanitizer_test.exs
git commit -m "feat: delegate sanitization to :sanitizer_adapter when configured

When sanitize_html is true and an Exoplanet.Sanitizer adapter is set,
it replaces the built-in tree-walk. strip_images/excerpt still apply.

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Complete the adapter test coverage

**Files:**
- Modify: `test/exoplanet/filters_sanitizer_test.exs`

- [ ] **Step 1: Add the remaining fake adapters and tests**

Append these adapters (inside the module, after `PassthroughSanitizer`) and tests (after the existing test). The recording adapter uses an `Agent` started per test via `start_supervised!` (the repo prefers `start_supervised!/2` in tests).

Add adapters:

```elixir
  # Removes the literal marker "SECRET" — proves the adapter's effect lands.
  defmodule RedactingSanitizer do
    @behaviour Exoplanet.Sanitizer
    @impl true
    def sanitize(html), do: String.replace(html, "SECRET", "***")
  end

  # Records every input it sees in an Agent named __MODULE__, then returns the
  # html unchanged. Lets tests assert which fields the adapter was called with.
  defmodule RecordingSanitizer do
    @behaviour Exoplanet.Sanitizer

    def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
    def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)

    @impl true
    def sanitize(html) do
      Agent.update(__MODULE__, &[html | &1])
      html
    end
  end
```

Add tests:

```elixir
  test "the adapter's transformation appears in body and summary" do
    Application.put_env(:exoplanet, :sanitizer_adapter, RedactingSanitizer)

    [out] =
      Filters.apply(
        [post(%{body: "<p>SECRET body</p>", summary: "<p>SECRET summary</p>"})],
        filters()
      )

    assert out.body == "<p>*** body</p>"
    assert out.summary == "<p>*** summary</p>"
  end

  test "the adapter is not called when sanitize_html is false" do
    start_supervised!(RecordingSanitizer)
    Application.put_env(:exoplanet, :sanitizer_adapter, RecordingSanitizer)

    html = ~s(<p>hi</p><iframe></iframe>)
    [out] = Filters.apply([post(%{body: html})], filters(%{sanitize_html: false}))

    assert RecordingSanitizer.calls() == []
    # No sanitization at all: body is untouched (iframe survives).
    assert out.body == html
  end

  test "the adapter is called once per non-empty field, skipping nil/empty" do
    start_supervised!(RecordingSanitizer)
    Application.put_env(:exoplanet, :sanitizer_adapter, RecordingSanitizer)

    Filters.apply([post(%{body: "<p>b</p>", summary: ""})], filters())
    # body is sanitized; summary "" is skipped; nil fields are skipped.
    assert RecordingSanitizer.calls() == ["<p>b</p>"]
  end

  test "strip_images runs after the adapter" do
    Application.put_env(:exoplanet, :sanitizer_adapter, PassthroughSanitizer)

    html = ~s(<p>x</p><img src="https://e/x.png" alt="Pic">)
    [out] = Filters.apply([post(%{body: html})], filters(%{strip_images: true}))

    # Adapter kept the <img>; the strip pass then rewrote it to a text link.
    refute out.body =~ "<img"
    assert out.body =~ ~s(<a href="https://e/x.png">Pic</a>)
  end

  test "with no adapter configured, output matches the built-in sanitizer" do
    # :sanitizer_adapter is unset (setup deletes it on exit; not set here).
    html = ~s(<p>ok</p><script>evil()</script>)
    [out] = Filters.apply([post(%{body: html})], filters())

    refute out.body =~ "<script"
    assert out.body =~ "<p>ok</p>"
  end
```

- [ ] **Step 2: Run the file**

Run: `mix test test/exoplanet/filters_sanitizer_test.exs`
Expected: PASS (6 tests, 0 failures). If the strip-images replacement assertion differs, open `lib/exoplanet/filters.ex` `image_replacement/2` to confirm the exact `<a href=...>alt</a>` shape and match it (do not weaken the assertion).

- [ ] **Step 3: Run the full suite**

Run: `mix test`
Expected: PASS, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add test/exoplanet/filters_sanitizer_test.exs
git commit -m "test: cover sanitizer adapter replace/skip/strip-order cases

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Filters moduledoc note

**Files:**
- Modify: `lib/exoplanet/filters.ex` (moduledoc, lib/exoplanet/filters.ex:2-24)

- [ ] **Step 1: Add a sanitizer-adapter paragraph to the moduledoc**

After the existing paragraph that ends `...consider pairing it with a dedicated sanitizer such as \`html_sanitize_ex\`.` (lib/exoplanet/filters.ex:11-13), insert this paragraph (before the `## Category filters` heading):

```elixir

  To delegate sanitization entirely, configure an `Exoplanet.Sanitizer`
  adapter:

      config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer

  When set (and `sanitize_html` is `true`), the adapter replaces the built-in
  sanitize step. `strip_images` and `excerpt_length` still apply, after the
  adapter. See `Exoplanet.Sanitizer`.
```

- [ ] **Step 2: Verify docs build**

Run: `mix docs --warnings-as-errors`
Expected: exit 0. (`Exoplanet.Sanitizer` is a public module, so the autolink resolves; no `skip_code_autolink_to` change needed.)

- [ ] **Step 3: Commit**

```bash
git add lib/exoplanet/filters.ex
git commit -m "docs: note sanitizer_adapter in Exoplanet.Filters moduledoc

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: README, CHANGELOG, CLAUDE.md

Per the repo's documentation-edit rule, verify references before editing.

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Verify the referenced module/key exist**

Run:
```bash
grep -n "defmodule Exoplanet.Sanitizer" lib/exoplanet/sanitizer.ex
grep -n "sanitizer_adapter" lib/exoplanet/filters.ex
```
Expected: the behaviour module is defined; `sanitizer_adapter` is read in Filters.

- [ ] **Step 2: Extend the README sanitization note**

In `README.md`, the section `### A note on HTML sanitization` ends with the sentence pointing at `html_sanitize_ex` (README.md:73-74). Immediately after that paragraph (before the `Note that \`Exoplanet.Config.from_file/1\`...` paragraph), insert:

```markdown

To delegate sanitization to such a library, implement the
`Exoplanet.Sanitizer` behaviour and configure it:

```elixir
defmodule MyApp.FeedSanitizer do
  @behaviour Exoplanet.Sanitizer

  @impl true
  def sanitize(html), do: HtmlSanitizeEx.basic_html(html)
end
```

```elixir
# config/config.exs
config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer
```

When configured (and `sanitize_html` is `true`), the adapter **replaces** the
built-in sanitizer. `html_sanitize_ex` is not a dependency of Exoplanet — add
it to your own application.
```

- [ ] **Step 3: Add a CHANGELOG entry**

In `CHANGELOG.md`, under `## [unreleased]` → `### Added` (CHANGELOG.md:49), add as the first bullet:

```markdown
- `Exoplanet.Sanitizer` behaviour: optionally delegate HTML sanitization to a
  comprehensive library (e.g. `html_sanitize_ex`) via
  `config :exoplanet, sanitizer_adapter: MyAdapter`. When set, the adapter
  replaces the built-in sanitizer.
```

- [ ] **Step 4: Add the CLAUDE.md architecture bullet**

In `CLAUDE.md`, the `Exoplanet.Cache` bullet is the last Architecture bullet. Add a new bullet immediately after it:

```markdown
- `Exoplanet.Sanitizer` — optional behaviour for delegating HTML sanitization. Implement `sanitize/1` and activate with `Application.put_env(:exoplanet, :sanitizer_adapter, MyAdapter)` (or `config :exoplanet, sanitizer_adapter: ...`). When set and `sanitize_html` is `true`, the adapter replaces `Exoplanet.Filters`' built-in sanitize walk; `strip_images`/`excerpt_length` still apply afterward. `html_sanitize_ex` is the documented example adapter and is not a dependency.
```

Also, in the existing `Exoplanet.Filters` bullet, after the description of the built-in sanitizer, the reader should know it is delegable. Append to that bullet's sentence about `sanitize_html`: ` A configured \`Exoplanet.Sanitizer\` adapter replaces this built-in sanitizer (see that module).` — verify the exact current wording first with `grep -n "sanitize_html: true" CLAUDE.md` and append the sentence at the natural end of the Filters bullet.

- [ ] **Step 5: Verify docs build (README/CHANGELOG are ex_doc extras)**

Run: `mix docs --warnings-as-errors`
Expected: exit 0 (no "references module … but it is hidden" — `Exoplanet.Sanitizer` is public).

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md CLAUDE.md
git commit -m "docs: document Exoplanet.Sanitizer adapter (README, CHANGELOG, CLAUDE)

Refs #24

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full precommit**

Run: `mix precommit`
Expected: PASS (compile, format, deps.unlock, docs, test all clean). If unavailable: `mix compile --warnings-as-errors && mix format --check-formatted && mix docs --warnings-as-errors && mix test`.

- [ ] **Step 2: Confirm no new dependency was added**

Run: `git diff main -- mix.exs mix.lock`
Expected: no `html_sanitize_ex` entry (the adapter is documented, not depended on).

- [ ] **Step 3: Confirm the built-in path is untouched for the no-adapter case**

Run: `mix test test/exoplanet/filters_test.exs`
Expected: PASS — the existing filter tests (no adapter) are green, proving the common path is unchanged.

---

## Self-Review Notes

- **Spec coverage:** behaviour module (Task 1), Filters wiring with replace semantics + helpers (Task 2), all six test cases — replace, effect-lands, skip-when-false, strip-after-adapter, no-adapter-unchanged, per-field/skip-empty (Tasks 2-3), Filters moduledoc (Task 4), README/CHANGELOG/CLAUDE docs (Task 5), no-dep + regression verification (Task 6). All spec sections mapped.
- **Replace semantics** consistently encoded: adapter branch is gated by `sanitize? and adapter`; `sanitize_html: false` skips the adapter (Task 3 test 2).
- **Type/name consistency:** `sanitizer_adapter/0`, `run_adapter/2`, `adapter_sanitize/2`, `strip_images_only/2`, `Exoplanet.Sanitizer.sanitize/1` used consistently across tasks.
- **No public-API/struct change:** filter map schema (`@type t`, `@defaults`, `Config`) untouched — the adapter is app-env only.

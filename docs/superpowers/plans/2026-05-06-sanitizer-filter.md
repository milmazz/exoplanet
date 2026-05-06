# HTML Sanitizer Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move HTML sanitization from `PlanetBEAM.Blog.HtmlSanitizer` into `Exoplanet.Filters` so all exoplanet consumers benefit, then remove the duplicated code from planet_beam.

**Architecture:** Three new keys (`sanitize_html`, `dropped_tags`, `dropped_attrs`) are added to `Exoplanet.Filters.t()` and wired into `transform/2` as the first step, before image stripping and excerpt generation. `sanitize_html` defaults to `true` in `Config.defstruct` so existing consumers get protection automatically on the next version bump. `dropped_tags` and `dropped_attrs` follow replace semantics (per-feed list replaces global default). The scrubbing logic is private functions inside `Exoplanet.Filters`, mirroring `HtmlSanitizer` but parameterised from the filter map.

**Tech Stack:** Elixir, `LazyHTML` (already a dep), ExUnit

---

## File Map

| File | What changes |
|---|---|
| `test/exoplanet/filters_test.exs` | Update `filters/1` helper; add `describe "apply/2 — sanitize_html"` |
| `lib/exoplanet/filters.ex` | Add 3 keys to `@type t`; add `apply_sanitization/2` call in `transform/2`; add three private functions |
| `lib/exoplanet/config.ex` | Add 3 keys with defaults to `default_filters` in `defstruct` |
| `CHANGELOG.md` | Entry under `## [unreleased]` |
| `mix.exs` (exoplanet) | Bump `@version` to `"0.4.0"` |
| `planet_beam/lib/planet_beam/blog/html_sanitizer.ex` | Delete (Task 4, after exoplanet release) |
| `planet_beam/lib/planet_beam/blog.ex` | Remove alias + 2 `Map.update!` calls (Task 4) |
| `planet_beam/mix.exs` | Remove `lazy_html` dep; bump `exoplanet` to `"~> 0.4"` (Task 4) |

---

## Task 1: Write failing sanitization tests

**Files:**
- Modify: `test/exoplanet/filters_test.exs`

- [ ] **Step 1: Update the `filters/1` test helper to include the three new keys**

  The helper at the bottom of the file currently has 4 keys. Add the 3 new ones. Note `sanitize_html: false` is the test-helper default (keeps existing tests unaffected); the real production default lives in `Config.defstruct`.

  ```elixir
  # Replace the existing filters/1 helper:
  defp filters(overrides \\ []) do
    Map.merge(
      %{
        allow_categories: [],
        block_categories: [],
        strip_images: false,
        excerpt_length: nil,
        sanitize_html: false,
        dropped_tags: ~w(iframe script object embed),
        dropped_attrs: ~w(style)
      },
      Map.new(overrides)
    )
  end
  ```

- [ ] **Step 2: Add the `describe "apply/2 — sanitize_html"` block**

  Insert the following block after the `describe "apply/2 — excerpt_length"` block, before the `filters/1` and `post/1` helper definitions at the bottom of the file:

  ```elixir
  describe "apply/2 — sanitize_html" do
    test "drops the full subtree of a dropped tag from body" do
      post = post(body: "<p>Good</p><iframe src=\"evil.com\"></iframe>")
      [result] = Filters.apply([post], filters(sanitize_html: true))
      refute result.body =~ "iframe"
      assert result.body =~ "Good"
    end

    test "strips dropped attributes from remaining elements" do
      post = post(body: ~s(<p style="color:red">Text</p>))
      [result] = Filters.apply([post], filters(sanitize_html: true))
      refute result.body =~ "style"
      assert result.body =~ "Text"
    end

    test "sanitize_html: false leaves content unchanged" do
      body = ~s(<iframe src="evil.com"></iframe><p style="color:red">Text</p>)
      post = post(body: body)
      [result] = Filters.apply([post], filters(sanitize_html: false))
      assert result.body == body
    end

    test "per-feed dropped_tags replaces the default — iframe survives when only script is dropped" do
      body = ~s(<script>evil()</script><iframe src="x.com"></iframe>)
      post = post(body: body)
      [result] = Filters.apply([post], filters(sanitize_html: true, dropped_tags: ~w(script)))
      refute result.body =~ "script"
      assert result.body =~ "iframe"
    end

    test "nil body and nil summary pass through unchanged" do
      post = post(body: nil, summary: nil)
      [result] = Filters.apply([post], filters(sanitize_html: true))
      assert result.body == nil
      assert result.summary == nil
    end

    test "empty string body passes through unchanged" do
      post = post(body: "")
      [result] = Filters.apply([post], filters(sanitize_html: true))
      assert result.body == ""
    end

    test "sanitizes before strip_images: iframe removed, img replaced by link" do
      body = ~s(<iframe src="bad.com"></iframe><img src="pic.jpg" alt="Photo">)
      post = post(body: body)
      [result] = Filters.apply([post], filters(sanitize_html: true, strip_images: true))
      refute result.body =~ "iframe"
      refute result.body =~ "<img"
      assert result.body =~ ~s(href="pic.jpg")
      assert result.body =~ "Photo"
    end
  end
  ```

- [ ] **Step 3: Run the new tests and confirm they fail**

  ```bash
  mix test test/exoplanet/filters_test.exs
  ```

  Expected: the 7 new tests fail (assertions about iframe/style being absent fail because `apply/2` doesn't sanitize yet). All pre-existing tests still pass.

---

## Task 2: Implement the sanitization filter

**Files:**
- Modify: `lib/exoplanet/filters.ex`
- Modify: `lib/exoplanet/config.ex`

- [ ] **Step 1: Update `Filters.t()` to include the three new keys**

  In `lib/exoplanet/filters.ex`, replace the existing `@type t` definition:

  ```elixir
  @type t :: %{
          allow_categories: [String.t()],
          block_categories: [String.t()],
          strip_images: boolean(),
          excerpt_length: pos_integer() | nil,
          sanitize_html: boolean(),
          dropped_tags: [String.t()],
          dropped_attrs: [String.t()]
        }
  ```

- [ ] **Step 2: Update `Config.defstruct` to include the three new keys with production defaults**

  In `lib/exoplanet/config.ex`, replace the `default_filters:` entry in `defstruct`:

  ```elixir
  default_filters: %{
    allow_categories: [],
    block_categories: [],
    strip_images: false,
    excerpt_length: nil,
    sanitize_html: true,
    dropped_tags: ~w(iframe script object embed),
    dropped_attrs: ~w(style)
  }
  ```

- [ ] **Step 3: Wire `apply_sanitization/2` into `transform/2`**

  In `lib/exoplanet/filters.ex`, replace the existing `transform/2` private function:

  ```elixir
  defp transform(post, filters) do
    post
    |> apply_sanitization(filters)
    |> apply_image_stripping(filters)
    |> apply_excerpt(filters)
  end
  ```

- [ ] **Step 4: Add the three private sanitization functions**

  Add the following private functions in `lib/exoplanet/filters.ex`, immediately before `apply_image_stripping/2`:

  ```elixir
  defp apply_sanitization(post, %{sanitize_html: false}), do: post

  defp apply_sanitization(post, %{dropped_tags: dropped_tags, dropped_attrs: dropped_attrs}) do
    post
    |> Map.update!(:body, &scrub_html(&1, dropped_tags, dropped_attrs))
    |> Map.update!(:summary, &scrub_html(&1, dropped_tags, dropped_attrs))
  end

  defp scrub_html(nil, _dropped_tags, _dropped_attrs), do: nil
  defp scrub_html("", _dropped_tags, _dropped_attrs), do: ""

  defp scrub_html(html, dropped_tags, dropped_attrs) when is_binary(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> Enum.flat_map(&scrub_node(&1, dropped_tags, dropped_attrs))
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
  end

  defp scrub_node({tag, attrs, children}, dropped_tags, dropped_attrs) when is_binary(tag) do
    if tag in dropped_tags do
      []
    else
      clean_attrs = Enum.reject(attrs, fn {name, _} -> name in dropped_attrs end)
      clean_children = Enum.flat_map(children, &scrub_node(&1, dropped_tags, dropped_attrs))
      [{tag, clean_attrs, clean_children}]
    end
  end

  defp scrub_node({:comment, _} = node, _dropped_tags, _dropped_attrs), do: [node]
  defp scrub_node(text, _dropped_tags, _dropped_attrs) when is_binary(text), do: [text]
  ```

- [ ] **Step 5: Run the full test suite**

  ```bash
  mix test
  ```

  Expected: all tests pass, including the 7 new sanitize_html tests and all pre-existing tests.

- [ ] **Step 6: Check formatting**

  ```bash
  mix format --check-formatted
  ```

  If it reports issues, run `mix format` then recheck.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/exoplanet/filters.ex lib/exoplanet/config.ex test/exoplanet/filters_test.exs
  git commit -m "feat: add sanitize_html filter — drop dangerous tags, strip style attrs"
  ```

---

## Task 3: CHANGELOG and version bump

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `mix.exs`

- [ ] **Step 1: Add CHANGELOG entry under `## [unreleased]`**

  In `CHANGELOG.md`, update the `## [unreleased]` section. If it already has a `### Added` block (from the dc:creator change), append to it; otherwise create the block:

  ```markdown
  ### Added

  - `Exoplanet.Filters` now sanitizes post bodies and summaries by default.
    Dangerous tags (`iframe`, `script`, `object`, `embed`) are removed entirely;
    `style` attributes are stripped from all remaining elements. Three new filter
    keys control the behaviour: `sanitize_html` (default `true`), `dropped_tags`
    (default `~w(iframe script object embed)`), and `dropped_attrs` (default
    `~w(style)`). All three follow the same per-feed override semantics as
    existing filter keys. Set `sanitize_html: false` per feed to opt out.
  ```

- [ ] **Step 2: Bump the library version**

  In `mix.exs`, change line 4:

  ```elixir
  @version "0.4.0"
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add CHANGELOG.md mix.exs
  git commit -m "chore: bump version to 0.4.0, update changelog"
  ```

---

## Task 4: Planet BEAM cleanup

> **Prerequisites:** Tasks 1–3 above are merged, and exoplanet 0.4.0 has been released to Hex.pm. Run these steps in the `planet_beam` repo.

**Files:**
- Delete: `lib/planet_beam/blog/html_sanitizer.ex`
- Modify: `lib/planet_beam/blog.ex`
- Modify: `mix.exs` (planet_beam)

- [ ] **Step 1: Delete the sanitizer module**

  Run from the `planet_beam/` directory:

  ```bash
  rm lib/planet_beam/blog/html_sanitizer.ex
  ```

- [ ] **Step 2: Remove sanitizer calls from `blog.ex`**

  In `lib/planet_beam/blog.ex`, remove line 7 (the alias):

  ```elixir
  # Delete this line:
  alias PlanetBEAM.Blog.HtmlSanitizer
  ```

  Then remove the two `Map.update!` calls in `store_in_persistent_term/2` (currently at lines 149–150):

  ```elixir
  # Delete these two lines:
  |> Map.update!(:body, &HtmlSanitizer.sanitize/1)
  |> Map.update!(:summary, &HtmlSanitizer.sanitize/1)
  ```

- [ ] **Step 3: Update `mix.exs`**

  In `planet_beam/mix.exs`, make two changes in `defp deps`:

  Remove the direct `lazy_html` dependency (it becomes a transitive dep via exoplanet):
  ```elixir
  # Delete this line:
  {:lazy_html, "~> 0.1"},
  ```

  Bump the exoplanet requirement:
  ```elixir
  # Change:
  {:exoplanet, "~> 0.3"},
  # To:
  {:exoplanet, "~> 0.4"},
  ```

- [ ] **Step 4: Fetch updated deps**

  ```bash
  mix deps.update exoplanet
  mix deps.get
  ```

- [ ] **Step 5: Run the full test suite**

  ```bash
  mix test
  ```

  Expected: all tests pass. If `lazy_html` is referenced somewhere else in planet_beam (unlikely but possible), the compiler will tell you — add it back as a direct dep in that case.

- [ ] **Step 6: Commit**

  ```bash
  git add lib/planet_beam/blog/html_sanitizer.ex lib/planet_beam/blog.ex mix.exs mix.lock
  git commit -m "chore: remove HtmlSanitizer — sanitization now handled by exoplanet 0.4"
  ```

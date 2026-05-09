# `:all` / `:none` Category Filter Semantics — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let exoplanet consumers express "no constraint" for category filters with the explicit atoms `allow_categories: :all` and `block_categories: :none`, normalizing both to `[]` internally and rejecting the inverses (`allow_categories: :none`, `block_categories: :all`).

**Architecture:** Single shared normalizer in `Exoplanet.Filters` invoked at two boundaries — `Filters.merge/2` and `Config.from_file/1`. The hot path (`apply/2`, `keep?/3`) is unchanged and continues to operate on lists. After exoplanet ships, planet_beam updates its `SiteConfig` defaults and the two motivating per-feed overrides in `planet-beam.exs`.

**Tech Stack:** Elixir, ExUnit. Two repos: `/Users/milmazz/Dev/elixir-lang/planet/exoplanet` and `/Users/milmazz/Dev/elixir-lang/planet/planet_beam`.

**Spec:** `exoplanet/docs/superpowers/specs/2026-05-09-categories-all-none-semantics-design.md`

**Branches:**
- `exoplanet`: `categories-all-none-semantics` (already created — verify with `git branch --show-current` before starting)
- `planet_beam`: create `categories-all-none-semantics` before any edit (PreToolUse hook blocks direct commits to `main`)

---

## File Structure

### exoplanet (modified)

| File | Responsibility | Change |
|------|----------------|--------|
| `lib/exoplanet/filters.ex` | Filter merge + apply | Add `normalize_categories/1` (public), call it from `merge/2`, widen `t()` typespec, update `@moduledoc` + `merge/2` `@doc` |
| `lib/exoplanet/config.ex` | Config struct + `from_file/1` | Call `Filters.normalize_categories/1` after the existing `Map.merge` of `default_filters` |
| `test/exoplanet/filters_test.exs` | Filter tests | Add a `describe "normalize_categories/1"` block; add merge/2 tests for atom inputs |
| `test/exoplanet/config_test.exs` | Config tests | Add a `from_file/1` test that loads `:all`/`:none` and asserts the normalized struct |
| `CHANGELOG.md` | Release notes | Add entry under `## [unreleased]` |

### planet_beam (modified)

| File | Responsibility | Change |
|------|----------------|--------|
| `mix.exs` | Dep declaration | Switch `{:exoplanet, "~> 0.4"}` to a path dep `{:exoplanet, path: "../exoplanet"}` so planet_beam consumes the unreleased local changes during verification |
| `lib/planet_beam/site_config.ex` | Defstruct defaults | `default_filters: %{allow_categories: :all, block_categories: :none, …}` |
| `planet-beam.exs` | Site config (lines 316, 320) | `filters: %{allow_categories: :all}` instead of `%{allow_categories: []}` |

---

## Part A — exoplanet

### Task A0: Verify branch

**Files:** none (read-only check)

- [ ] **Step 1: Confirm we are on the feature branch in exoplanet**

```bash
cd /Users/milmazz/Dev/elixir-lang/planet/exoplanet
git branch --show-current
```

Expected output: `categories-all-none-semantics`

If output is `main` (or anything else), STOP and create/switch the branch:

```bash
git switch categories-all-none-semantics 2>/dev/null || git switch -c categories-all-none-semantics
```

The PreToolUse hook will block any commit on `main`.

---

### Task A1: Failing tests for `Filters.normalize_categories/1`

**Files:**
- Test: `test/exoplanet/filters_test.exs`

- [ ] **Step 1: Add a new `describe` block at the top of the test module, just after `alias Exoplanet.Filters`**

Open `test/exoplanet/filters_test.exs` and insert this block immediately after the existing `alias Exoplanet.Filters` line (line 4) and before `describe "merge/2" do`:

```elixir
  describe "normalize_categories/1" do
    test "passes lists through unchanged" do
      input = %{allow_categories: ["a"], block_categories: ["b"]}
      assert Filters.normalize_categories(input) == input
    end

    test "normalizes allow_categories: :all to []" do
      assert Filters.normalize_categories(%{allow_categories: :all}) ==
               %{allow_categories: []}
    end

    test "normalizes block_categories: :none to []" do
      assert Filters.normalize_categories(%{block_categories: :none}) ==
               %{block_categories: []}
    end

    test "leaves unrelated keys untouched" do
      input = %{allow_categories: :all, strip_images: true, drop_tags: ["x"]}
      assert Filters.normalize_categories(input) ==
               %{allow_categories: [], strip_images: true, drop_tags: ["x"]}
    end

    test "leaves missing keys missing (no defaults inserted)" do
      assert Filters.normalize_categories(%{}) == %{}
    end

    test "raises ArgumentError for allow_categories: :none" do
      assert_raise ArgumentError, ~r/:allow_categories does not accept :none/, fn ->
        Filters.normalize_categories(%{allow_categories: :none})
      end
    end

    test "raises ArgumentError for block_categories: :all" do
      assert_raise ArgumentError, ~r/:block_categories does not accept :all/, fn ->
        Filters.normalize_categories(%{block_categories: :all})
      end
    end

    test "raises ArgumentError for unrecognized atom in allow_categories" do
      assert_raise ArgumentError, ~r/:allow_categories must be a list of strings or :all/, fn ->
        Filters.normalize_categories(%{allow_categories: :foo})
      end
    end

    test "raises ArgumentError for unrecognized atom in block_categories" do
      assert_raise ArgumentError, ~r/:block_categories must be a list of strings or :none/, fn ->
        Filters.normalize_categories(%{block_categories: :foo})
      end
    end
  end

```

- [ ] **Step 2: Run the new tests to verify they fail with "function not defined"**

```bash
mix test test/exoplanet/filters_test.exs --only describe:"normalize_categories/1" 2>&1 | tail -30
```

(If the `--only describe:` filter doesn't isolate them, just run the whole file; the new tests will be the only ones failing.)

Expected: failures for all nine tests with errors like `undefined function Exoplanet.Filters.normalize_categories/1` or `(UndefinedFunctionError)`.

---

### Task A2: Implement `normalize_categories/1`

**Files:**
- Modify: `lib/exoplanet/filters.ex`

- [ ] **Step 1: Add the public function and its private helper**

Insert this block in `lib/exoplanet/filters.ex` immediately after the `defaults/0` function (after line 36, before the `@doc` for `merge/2` at line 38):

```elixir

  @doc """
  Normalizes the category-filter atoms in a filter map.

  Replaces `allow_categories: :all` with `[]` and `block_categories: :none`
  with `[]`. Lists pass through unchanged. Keys that are missing stay
  missing (no defaults are inserted). Raises `ArgumentError` for any
  other atom value, including `allow_categories: :none` and
  `block_categories: :all` (both nonsensical — drop the feed instead).

  Called automatically by `merge/2` and `Exoplanet.Config.from_file/1`,
  so consumers rarely need to invoke it directly.
  """
  @spec normalize_categories(map()) :: map()
  def normalize_categories(filters) when is_map(filters) do
    filters
    |> normalize_key(:allow_categories, :all, :none)
    |> normalize_key(:block_categories, :none, :all)
  end

  defp normalize_key(filters, key, ok_atom, bad_atom) do
    case Map.fetch(filters, key) do
      :error ->
        filters

      {:ok, list} when is_list(list) ->
        filters

      {:ok, ^ok_atom} ->
        Map.put(filters, key, [])

      {:ok, ^bad_atom} ->
        raise ArgumentError,
              "#{inspect(key)} does not accept #{inspect(bad_atom)} " <>
                "(valid forms are a list of strings or #{inspect(ok_atom)})"

      {:ok, other} ->
        raise ArgumentError,
              "#{inspect(key)} must be a list of strings or #{inspect(ok_atom)}, " <>
                "got: #{inspect(other)}"
    end
  end

```

- [ ] **Step 2: Run the new tests to verify they pass**

```bash
mix test test/exoplanet/filters_test.exs 2>&1 | tail -20
```

Expected: all tests pass. The error messages must match the regexes in Task A1, in particular:

- `:allow_categories does not accept :none (valid forms are a list of strings or :all)`
- `:block_categories does not accept :all (valid forms are a list of strings or :none)`
- `:allow_categories must be a list of strings or :all, got: :foo`
- `:block_categories must be a list of strings or :none, got: :foo`

If any of those fails, fix the message in `normalize_key/4` before moving on.

- [ ] **Step 3: Commit**

```bash
git add lib/exoplanet/filters.ex test/exoplanet/filters_test.exs
git commit -m "$(cat <<'EOF'
feat: add Filters.normalize_categories/1

Translates allow_categories: :all → [] and block_categories: :none → [],
raises ArgumentError on the inverses (allow :none / block :all) and on
unrecognized atoms. Lists and missing keys pass through unchanged.

Not yet wired into merge/2 or Config.from_file/1; that comes in the
following commits so each step is independently testable.
EOF
)"
```

---

### Task A3: Failing tests for `merge/2` accepting atoms

**Files:**
- Test: `test/exoplanet/filters_test.exs`

- [ ] **Step 1: Add tests inside the existing `describe "merge/2"` block**

Insert these tests immediately after the existing test `"per_feed nil values leave the default in place"` (after line 64, still inside `describe "merge/2" do`):

```elixir

    test "per_feed allow_categories: :all normalizes to []" do
      result = Filters.merge(merge_defaults(), %{allow_categories: :all})
      assert result.allow_categories == []
      assert result.block_categories == ["personal"]
    end

    test "per_feed block_categories: :none normalizes to []" do
      result = Filters.merge(merge_defaults(), %{block_categories: :none})
      assert result.block_categories == []
      assert result.allow_categories == ["elixir", "erlang"]
    end

    test "defaults-side allow_categories: :all is also normalized" do
      defaults = filters(allow_categories: :all, block_categories: ["spam"])
      result = Filters.merge(defaults, %{})
      assert result.allow_categories == []
      assert result.block_categories == ["spam"]
    end

    test "defaults-side block_categories: :none is also normalized" do
      defaults = filters(allow_categories: ["elixir"], block_categories: :none)
      result = Filters.merge(defaults, %{})
      assert result.allow_categories == ["elixir"]
      assert result.block_categories == []
    end

    test "raises ArgumentError for per_feed allow_categories: :none" do
      assert_raise ArgumentError, ~r/:allow_categories does not accept :none/, fn ->
        Filters.merge(merge_defaults(), %{allow_categories: :none})
      end
    end

    test "raises ArgumentError for per_feed block_categories: :all" do
      assert_raise ArgumentError, ~r/:block_categories does not accept :all/, fn ->
        Filters.merge(merge_defaults(), %{block_categories: :all})
      end
    end
```

Note: the `filters/1` test helper at the bottom of the file builds on `Filters.defaults() | sanitize_html: false` and overlays the keyword overrides via `Map.merge`, so passing `allow_categories: :all` produces a map with `allow_categories: :all` literally — exactly what we want for these "defaults-side" tests.

- [ ] **Step 2: Run the file and confirm the six new tests fail**

```bash
mix test test/exoplanet/filters_test.exs 2>&1 | tail -30
```

Expected: the four "normalizes / is normalized" tests fail with assertion errors (the atom value is still in the merged map); the two "raises ArgumentError" tests fail because no error is raised.

---

### Task A4: Wire normalization into `merge/2`

**Files:**
- Modify: `lib/exoplanet/filters.ex` (the `merge/2` function)

- [ ] **Step 1: Replace both `merge/2` clauses**

In `lib/exoplanet/filters.ex`, find the `merge/2` clauses (lines 46–53):

```elixir
  def merge(defaults, nil), do: defaults

  def merge(defaults, per_feed) do
    Map.merge(defaults, per_feed, fn
      _k, v1, nil -> v1
      _k, _v1, v2 -> v2
    end)
  end
```

Replace with:

```elixir
  def merge(defaults, nil), do: normalize_categories(defaults)

  def merge(defaults, per_feed) do
    defaults
    |> normalize_categories()
    |> Map.merge(normalize_categories(per_feed), fn
      _k, v1, nil -> v1
      _k, _v1, v2 -> v2
    end)
  end
```

Why normalize both sides: a per-feed map that omits `allow_categories` must not let an atom-valued default leak through; a per-feed map that overrides `allow_categories: :all` must be normalized before `Map.merge` so the merged result has `[]`, not `:all`.

- [ ] **Step 2: Update the `@doc` for `merge/2`**

Replace the existing `@doc` for `merge/2` (lines 38–44) with:

```elixir
  @doc """
  Merges a per-feed filter map onto a default filter map.

  `allow_categories` and `block_categories` REPLACE the default value when
  the per-feed map sets them to a list. Other keys override field-by-field.
  Per-feed keys set to `nil` leave the default in place.

  Both maps are passed through `normalize_categories/1` first, so callers
  may use `allow_categories: :all` or `block_categories: :none` on either
  side. Invalid atoms (`allow_categories: :none`, `block_categories: :all`,
  or any unrecognized atom) raise `ArgumentError`.
  """
```

- [ ] **Step 3: Run the full filters test file and verify all tests pass**

```bash
mix test test/exoplanet/filters_test.exs 2>&1 | tail -10
```

Expected: all tests pass (existing and new).

- [ ] **Step 4: Commit**

```bash
git add lib/exoplanet/filters.ex test/exoplanet/filters_test.exs
git commit -m "$(cat <<'EOF'
feat: accept :all/:none atoms in Filters.merge/2

merge/2 now passes both the defaults-side and per-feed maps through
normalize_categories/1 before merging, so callers can use
`allow_categories: :all` or `block_categories: :none` interchangeably
with the empty-list form.
EOF
)"
```

---

### Task A5: Failing test for `Config.from_file/1` accepting atoms

**Files:**
- Test: `test/exoplanet/config_test.exs`

- [ ] **Step 1: Add a new test inside `describe "default_filters"`**

Insert this test in `test/exoplanet/config_test.exs` after the existing `"from_file/1 loads default_filters when present in the config file"` test (after line 48, still inside the `describe` block):

```elixir

    @tag :tmp_dir
    test "from_file/1 normalizes :all/:none atoms in default_filters", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.exs")

      File.write!(path, """
      %{
        sources: %{},
        default_filters: %{
          allow_categories: :all,
          block_categories: :none
        }
      }
      """)

      config = Config.from_file(path)

      assert config.default_filters.allow_categories == []
      assert config.default_filters.block_categories == []
    end

    @tag :tmp_dir
    test "from_file/1 raises for invalid atom in default_filters", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.exs")

      File.write!(path, """
      %{
        sources: %{},
        default_filters: %{allow_categories: :none}
      }
      """)

      assert_raise ArgumentError, ~r/:allow_categories does not accept :none/, fn ->
        Config.from_file(path)
      end
    end
```

- [ ] **Step 2: Run config tests and confirm both new tests fail**

```bash
mix test test/exoplanet/config_test.exs 2>&1 | tail -20
```

Expected: the "normalizes" test fails (atoms survive into the struct); the "raises" test fails (no error raised at config load).

---

### Task A6: Wire normalization into `Config.from_file/1`

**Files:**
- Modify: `lib/exoplanet/config.ex`

- [ ] **Step 1: Update `from_file/1` to normalize after the `Map.merge`**

In `lib/exoplanet/config.ex`, replace the `from_file/1` body (lines 46–50):

```elixir
  def from_file(path) when is_binary(path) do
    {attrs, _} = Code.eval_file(path)
    config = struct!(__MODULE__, Map.take(attrs, recognized_keys()))
    %{config | default_filters: Map.merge(Exoplanet.Filters.defaults(), config.default_filters)}
  end
```

With:

```elixir
  def from_file(path) when is_binary(path) do
    {attrs, _} = Code.eval_file(path)
    config = struct!(__MODULE__, Map.take(attrs, recognized_keys()))

    merged_filters =
      Exoplanet.Filters.defaults()
      |> Map.merge(config.default_filters)
      |> Exoplanet.Filters.normalize_categories()

    %{config | default_filters: merged_filters}
  end
```

- [ ] **Step 2: Run all config and filters tests**

```bash
mix test test/exoplanet/config_test.exs test/exoplanet/filters_test.exs 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/exoplanet/config.ex test/exoplanet/config_test.exs
git commit -m "$(cat <<'EOF'
feat: normalize :all/:none atoms in Config.from_file/1

Without normalization at the config-load boundary, a user-supplied
default_filters with atom values would only get normalized when a
per-feed merge/2 ran. Feeds with no per-feed filters: skip merge/2
(it returns defaults unchanged), so Config.from_file/1 must do the
normalization itself.
EOF
)"
```

---

### Task A7: Widen `Filters.t()` typespec and update `@moduledoc`

**Files:**
- Modify: `lib/exoplanet/filters.ex`

- [ ] **Step 1: Update the `t()` typespec**

In `lib/exoplanet/filters.ex`, replace the existing `@type t` (lines 10–18):

```elixir
  @type t :: %{
          allow_categories: [String.t()],
          block_categories: [String.t()],
          strip_images: boolean(),
          excerpt_length: pos_integer() | nil,
          sanitize_html: boolean(),
          drop_tags: [String.t()],
          drop_attrs: [String.t()]
        }
```

With:

```elixir
  @type t :: %{
          allow_categories: [String.t()] | :all,
          block_categories: [String.t()] | :none,
          strip_images: boolean(),
          excerpt_length: pos_integer() | nil,
          sanitize_html: boolean(),
          drop_tags: [String.t()],
          drop_attrs: [String.t()]
        }
```

- [ ] **Step 2: Update the `@moduledoc` to mention the atoms**

Replace the existing `@moduledoc` (lines 2–8):

```elixir
  @moduledoc """
  Per-feed content filters: HTML sanitization, category allow/block lists,
  image stripping, and summary truncation. The sanitizer removes dangerous
  tags and style attributes but the *default configuration* does not filter
  attribute-based injection vectors such as `on*` event handlers or
  `javascript:` URIs.
  """
```

With:

```elixir
  @moduledoc """
  Per-feed content filters: HTML sanitization, category allow/block lists,
  image stripping, and summary truncation. The sanitizer removes dangerous
  tags and style attributes but the *default configuration* does not filter
  attribute-based injection vectors such as `on*` event handlers or
  `javascript:` URIs.

  ## Category filters

  `allow_categories` accepts a list of strings or `:all` (no allowlist
  constraint). `block_categories` accepts a list of strings or `:none` (no
  blocklist constraint). The empty list `[]` is equivalent to `:all` /
  `:none` respectively and remains supported. Atoms are normalized to `[]`
  internally; see `normalize_categories/1`. The inverses
  (`allow_categories: :none`, `block_categories: :all`) raise
  `ArgumentError` — drop the feed entirely if you want zero posts.
  """
```

- [ ] **Step 3: Run the full test suite to confirm nothing broke**

```bash
mix test 2>&1 | tail -10
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/exoplanet/filters.ex
git commit -m "$(cat <<'EOF'
docs: widen Filters.t() typespec to admit :all/:none atoms

Documents the public API shape; dialyzer will accept both forms from
callers. The internal post-normalization shape is still always lists.
EOF
)"
```

---

### Task A8: CHANGELOG entry

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add an entry under `## [unreleased]`**

In `CHANGELOG.md`, replace:

```
## [unreleased]

## [0.4.1] - 2026-05-06
```

With:

```
## [unreleased]

### Added

- `Exoplanet.Filters` now accepts `allow_categories: :all` and
  `block_categories: :none` to express "no constraint" explicitly.
  Lists keep working unchanged; atoms are normalized to `[]` internally.
  Invalid atoms (`allow_categories: :none`, `block_categories: :all`, or
  any unrecognized atom) raise `ArgumentError` at config-load / merge
  time. The `Exoplanet.Filters.t()` typespec is widened accordingly.

## [0.4.1] - 2026-05-06
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for :all/:none category filter atoms"
```

---

### Task A9: Run `mix precommit`

**Files:** none (verification gate)

- [ ] **Step 1: Run the full precommit check**

```bash
mix precommit 2>&1 | tail -40
```

Expected: clean exit (compile, format, deps.unlock, docs, test all pass). If any step fails, fix it on this branch and re-run before moving to Part B.

Common things to check if it fails:
- `mix format` may reformat the code blocks above slightly — run `mix format` and amend the most recent commit with `git commit --amend --no-edit` only if the only change is formatting from the same logical step (otherwise commit separately).
- `mix docs` will fail if there's a typo in a `@doc` reference; check the doctest output.

- [ ] **Step 2: Show the commit log for this branch**

```bash
git log --oneline main..HEAD
```

Expected: 5 commits (spec doc commits from earlier sessions are also here; that's fine):
- spec doc(s)
- feat: add Filters.normalize_categories/1
- feat: accept :all/:none atoms in Filters.merge/2
- feat: normalize :all/:none atoms in Config.from_file/1
- docs: widen Filters.t() typespec to admit :all/:none atoms
- docs: changelog for :all/:none category filter atoms

---

## Part B — planet_beam

> **Important:** Part B can only be verified after Part A's code is committed locally. Part B uses a path dep so we don't depend on a hex publish.

### Task B0: Create planet_beam feature branch

**Files:** none (branch creation only)

- [ ] **Step 1: Switch to planet_beam and confirm branch state**

```bash
cd /Users/milmazz/Dev/elixir-lang/planet/planet_beam
git status -sb
```

Expected: `## main...origin/main` (or similar) with no uncommitted edits to the files we are about to touch (`mix.exs`, `lib/planet_beam/site_config.ex`, `planet-beam.exs`).

- [ ] **Step 2: Create and switch to the feature branch**

```bash
git switch -c categories-all-none-semantics
git branch --show-current
```

Expected: `categories-all-none-semantics`

The PreToolUse hook will block commits on `main`; this step prevents that.

---

### Task B1: Switch exoplanet to a path dep for local verification

**Files:**
- Modify: `mix.exs`

- [ ] **Step 1: Replace the exoplanet dep line in `mix.exs`**

In `mix.exs`, find:

```elixir
      {:exoplanet, "~> 0.4"},
```

Replace with:

```elixir
      {:exoplanet, path: "../exoplanet"},
```

This consumes the local sibling repo containing the unreleased changes.

- [ ] **Step 2: Refresh the dep**

```bash
mix deps.unlock exoplanet && mix deps.get
```

Expected: `mix.lock` updated; no fetch errors.

- [ ] **Step 3: Compile to confirm the path dep resolves**

```bash
mix compile 2>&1 | tail -10
```

Expected: clean compile (a few warnings from other deps are fine; no errors).

- [ ] **Step 4: Commit**

```bash
git add mix.exs mix.lock
git commit -m "$(cat <<'EOF'
chore: switch exoplanet to path dep for local verification

Consumes the unreleased sibling repo carrying the :all/:none category
filter atoms. Will revert to a hex version constraint after exoplanet
ships.
EOF
)"
```

---

### Task B2: Update `SiteConfig` defstruct defaults

**Files:**
- Modify: `lib/planet_beam/site_config.ex` (lines 72–77)

- [ ] **Step 1: Replace the `default_filters` defstruct default**

In `lib/planet_beam/site_config.ex`, find:

```elixir
    default_filters: %{
      allow_categories: [],
      block_categories: [],
      strip_images: false,
      excerpt_length: nil
    },
```

Replace with:

```elixir
    default_filters: %{
      allow_categories: :all,
      block_categories: :none,
      strip_images: false,
      excerpt_length: nil
    },
```

This is a documentation improvement: the merged filter map exoplanet sees is identical (atoms normalize to `[]`), but the struct default is now self-explanatory.

- [ ] **Step 2: Run planet_beam tests**

```bash
mix test 2>&1 | tail -15
```

Expected: all tests pass. If any test asserts the literal value `[]` for these keys on the un-merged struct, update that assertion to use `:all` / `:none` (the value before normalization).

- [ ] **Step 3: Commit**

```bash
git add lib/planet_beam/site_config.ex
git commit -m "$(cat <<'EOF'
chore: use :all/:none for SiteConfig category-filter defaults

Functionally equivalent (exoplanet normalizes both atoms to []) but
makes the intent self-documenting: an empty list reads as "match
nothing", which is the opposite of how exoplanet treats it.
EOF
)"
```

---

### Task B3: Update `planet-beam.exs` per-feed overrides

**Files:**
- Modify: `planet-beam.exs` (lines 316 and 320)

- [ ] **Step 1: Replace both per-feed filter overrides**

In `planet-beam.exs`, find both occurrences of:

```elixir
          filters: %{allow_categories: []}
```

(lines 316 and 320, both inside the Oban entries).

Replace each with:

```elixir
          filters: %{allow_categories: :all}
```

This is the case that motivated the whole feature: an empty list reads as "an empty allowlist matches nothing" but actually means "no allowlist constraint, admit everything".

- [ ] **Step 2: Re-run tests and start the app to make sure config loads cleanly**

```bash
mix test 2>&1 | tail -10
```

Expected: all tests pass.

```bash
MIX_ENV=dev mix compile 2>&1 | tail -5
```

Expected: clean compile.

To verify the config file itself parses, run a one-shot eval:

```bash
mix run -e 'PlanetBEAM.SiteConfig.from_file("planet-beam.exs") |> PlanetBEAM.SiteConfig.to_exoplanet_config() |> then(&IO.inspect(&1.default_filters, label: "default_filters"))'
```

Expected: `default_filters: %{allow_categories: [], block_categories: [], …}` (atoms normalized to `[]` by exoplanet at the boundary). No `ArgumentError`.

- [ ] **Step 3: Commit**

```bash
git add planet-beam.exs
git commit -m "$(cat <<'EOF'
feat: use :all for Oban per-feed allowlist opt-out

The Oban feeds need to opt out of the planet-wide allowlist so their
posts are not filtered. The previous `allow_categories: []` form reads
as "an empty allowlist" but actually means "no allowlist constraint".
The new `:all` atom makes the intent obvious to any reader.
EOF
)"
```

---

### Task B4: Run `mix precommit` in planet_beam

**Files:** none (verification gate)

- [ ] **Step 1: Run the full precommit check**

```bash
mix precommit 2>&1 | tail -40
```

Expected: clean exit (compile, format, deps.unlock, hex.audit, test all pass).

Note: `hex.audit` may complain about the path dep on exoplanet (no hex audit data for an unpublished version). If it errors *only* on that, the warning is acceptable on this branch — note it in the next session and revert to a hex version constraint once exoplanet 0.5.0 ships.

- [ ] **Step 2: Show the commit log for this branch**

```bash
git log --oneline main..HEAD
```

Expected: 3 commits:
- chore: switch exoplanet to path dep for local verification
- chore: use :all/:none for SiteConfig category-filter defaults
- feat: use :all for Oban per-feed allowlist opt-out

---

## Done

Both branches are ready for review / PR. The plan does NOT:
- Bump exoplanet's version or tag a release (release decision; spec entry sits under `## [unreleased]` until then).
- Revert planet_beam's path dep back to a hex constraint (do that once exoplanet ships).
- Open PRs (do that manually after review).

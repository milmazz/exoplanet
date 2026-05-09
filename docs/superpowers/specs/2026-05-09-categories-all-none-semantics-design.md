# `:all` / `:none` semantics for category filters

## Problem

`Exoplanet.Filters` represents "no constraint" with an empty list:

- `allow_categories: []` means **allow every category** (no allowlist).
- `block_categories: []` means **block no category** (no blocklist).

Both readings are the *opposite* of what the literal value suggests. In
`planet_beam`'s `planet-beam.exs` two per-feed overrides today read
`filters: %{allow_categories: []}` to opt out of the planet-wide allowlist.
A maintainer scanning that file naturally reads it as "an empty allowlist —
i.e. nothing matches", which is the wrong mental model.

## Goal

Let consumers express "no constraint" with explicit atoms:

- `allow_categories: :all`  — no allowlist (admit every post).
- `block_categories: :none` — no blocklist (block no post).

Lists keep working unchanged. The change is purely additive at the public
boundary.

## Non-goals

- No deprecation, warning, or removal of the list-only forms (`[]` keeps
  meaning "no constraint" indefinitely).
- No new "allow nothing / block everything" affordance — those have no use
  case (drop the feed entirely instead). Specifically:
  - `allow_categories: :none` is rejected.
  - `block_categories: :all` is rejected.
- No change to other filter keys (`drop_tags`, `drop_attrs`,
  `sanitize_html`, `strip_images`, `excerpt_length`).

## Public API

`Exoplanet.Filters.t()` widens to:

```elixir
@type t :: %{
        allow_categories: [String.t()] | :all,
        block_categories: [String.t()] | :none,
        # ... other keys unchanged
      }
```

Accepted forms per key:

| Key                | Accepted                          | Rejected                |
|--------------------|-----------------------------------|-------------------------|
| `allow_categories` | `[String.t()]`, `:all`            | `:none`, any other atom |
| `block_categories` | `[String.t()]`, `:none`           | `:all`, any other atom  |

Rejected values raise `ArgumentError` at config-load / merge time.

## Internal representation

The merged `Filters.t()` map produced by `Exoplanet.Filters.merge/2`
**always holds lists** for both keys. Atoms are normalized to `[]` at the
boundary. The hot path in `apply/2` and `keep?/3` is unchanged: it
continues to operate on lists, with `[]` meaning "no constraint".

This keeps the semantic change isolated to a single normalization step and
avoids sprinkling atom checks throughout the filter pipeline.

## Where normalization happens

Two boundaries — both before any `apply/2` call sees the value:

1. **`Exoplanet.Filters.merge/2`** — normalizes `allow_categories` and
   `block_categories` in both the `defaults` map and the `per_feed` map
   (when present) before merging. This is the one path every per-feed
   filter map flows through, so it covers both library defaults and
   per-feed overrides.

2. **`Exoplanet.Config.from_file/1`** — normalizes the user-supplied
   `default_filters` after the existing `Map.merge(Filters.defaults(),
   user_default_filters)`. Without this, a user `default_filters: %{
   allow_categories: :all }` would survive into the struct as an atom and
   only get normalized when a per-feed `merge/2` happens — feeds with no
   per-feed `filters:` would skip the normalization. (`merge/2` is also
   called for those feeds, since the per-feed value is `nil`, but the
   `merge(defaults, nil)` clause returns `defaults` unchanged. So
   `default_filters` MUST be normalized at config load.)

A small private helper is shared by both call sites:

```elixir
# in Exoplanet.Filters

@spec normalize_categories(map()) :: map()
def normalize_categories(filters) when is_map(filters) do
  filters
  |> normalize_key(:allow_categories, :all, :none)
  |> normalize_key(:block_categories, :none, :all)
end

defp normalize_key(filters, key, ok_atom, bad_atom) do
  case Map.fetch(filters, key) do
    :error -> filters
    {:ok, list} when is_list(list) -> filters
    {:ok, ^ok_atom} -> Map.put(filters, key, [])
    {:ok, ^bad_atom} ->
      raise ArgumentError,
            "#{inspect(key)} does not accept #{inspect(bad_atom)} " <>
              "(got #{inspect(bad_atom)}; valid forms are a list of strings or #{inspect(ok_atom)})"
    {:ok, other} ->
      raise ArgumentError,
            "#{inspect(key)} must be a list of strings or #{inspect(ok_atom)}, got: #{inspect(other)}"
  end
end
```

Exposed as a public function (rather than `defp`) so `Config.from_file/1`
can call it without going through `merge/2`. This is the only new public
surface in `Exoplanet.Filters` besides the typespec change.

## Behavior matrix

After normalization the existing filter tests continue to apply unchanged.
New behavior to cover:

| Per-feed value          | Default value            | Effective list | Effect on posts                |
|-------------------------|--------------------------|----------------|--------------------------------|
| `allow_categories: :all`| (anything)               | `[]`           | No allowlist constraint        |
| `block_categories: :none`| (anything)              | `[]`           | No blocklist constraint        |
| `allow_categories: :none`| (anything)              | —              | `ArgumentError` at merge time  |
| `block_categories: :all`| (anything)               | —              | `ArgumentError` at merge time  |
| (key absent)            | `allow_categories: :all` | `[]`           | No allowlist constraint        |
| (key absent)            | `block_categories: :none`| `[]`           | No blocklist constraint        |

## Tests (exoplanet)

Added to `test/exoplanet/filters_test.exs`:

- `merge/2` accepts `allow_categories: :all` and normalizes to `[]`.
- `merge/2` accepts `block_categories: :none` and normalizes to `[]`.
- `merge/2` raises `ArgumentError` for `allow_categories: :none`.
- `merge/2` raises `ArgumentError` for `block_categories: :all`.
- `merge/2` raises `ArgumentError` for any unrecognized atom (e.g. `:foo`).
- `merge/2` normalizes atoms appearing on the **defaults** side too.
- A `Filters.apply/2` test with a merged map produced from `:all`/`:none`
  inputs behaves identically to one produced from `[]` inputs.

Added to `test/exoplanet/config_test.exs`:

- `Config.from_file/1` with a fixture that uses `:all`/`:none` in
  `default_filters` produces a struct whose `default_filters` are the
  normalized lists.

No existing tests change.

## CHANGELOG

A new entry under `## [unreleased]` in `CHANGELOG.md`:

```
### Added

- `Exoplanet.Filters` now accepts `allow_categories: :all` and
  `block_categories: :none` to express "no constraint" explicitly.
  Lists keep working unchanged; the atoms are normalized to `[]`
  internally. Invalid atoms (`allow_categories: :none`,
  `block_categories: :all`, or any unrecognized atom) raise
  `ArgumentError` at config-load / merge time.
```

## planet_beam follow-up

After exoplanet ships, in `planet_beam`:

1. `lib/planet_beam/site_config.ex` defstruct default — change to:

   ```elixir
   default_filters: %{
     allow_categories: :all,
     block_categories: :none,
     strip_images: false,
     excerpt_length: nil
   }
   ```

   Functionally equivalent (normalized to `[]` at the exoplanet boundary)
   but makes the intent self-documenting.

2. `planet-beam.exs` per-feed overrides at lines 316 and 320 — change
   `filters: %{allow_categories: []}` to `filters: %{allow_categories: :all}`.
   This is the case that motivates the change.

3. Bump the `exoplanet` dep to the new version.

No other planet_beam changes are required — `SiteConfig.to_exoplanet_config/1`
forwards the filter map verbatim and exoplanet does the normalization.

## Risks

- **Reading the source through an old version of exoplanet:** if a
  `planet-beam.exs` using `:all` is loaded with an exoplanet older than
  this change, `Filters.apply/2` would crash on `Enum.map(:all, ...)`. The
  dep bump in step 3 above is therefore not optional.
- **Other consumers:** the change is additive, so existing consumers are
  unaffected unless they were already passing the now-rejected atoms,
  which is implausible.

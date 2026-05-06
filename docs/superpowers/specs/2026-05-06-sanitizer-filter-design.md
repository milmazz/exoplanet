# Design: HTML Sanitizer Filter in Exoplanet

**Date:** 2026-05-06  
**Status:** Approved  
**Scope:** exoplanet library + planet_beam consumer cleanup

## Background

`PlanetBEAM.Blog.HtmlSanitizer` currently strips dangerous tags (`iframe`,
`script`, `object`, `embed`), removes `style` attributes, and normalises
malformed HTML by round-tripping through `LazyHTML`. It is applied once at
enrich-time in `Blog.store_in_persistent_term/2` on every post's `:body` and
`:summary`. Moving this into exoplanet's filter pipeline makes the protection
available to all consumers without duplicating the `lazy_html` dependency.

## Chosen Approach

Extend `Exoplanet.Filters` (Option A): add sanitization as private functions
alongside the existing image-stripping logic. No new public module is introduced.
`lazy_html` is already an exoplanet dependency.

## Section 1: Filter Type and Defaults

Three new keys are added to `Filters.t()` and to the `default_filters` map in
`Config.defstruct`:

| Key | Type | Default |
|---|---|---|
| `sanitize_html` | `boolean()` | `true` |
| `dropped_tags` | `[String.t()]` | `~w(iframe script object embed)` |
| `dropped_attrs` | `[String.t()]` | `~w(style)` |

`sanitize_html` defaults to `true` so every consumer gets sanitization on the
next version bump without any config change. Consumers who need raw HTML can
opt out per feed with `sanitize_html: false`.

## Section 2: Merge Semantics

- **`dropped_tags` / `dropped_attrs`** — **replace** semantics (same as
  `allow_categories` / `block_categories`). A per-feed list replaces the
  global default entirely. To extend the defaults a consumer repeats them in
  the per-feed list.
- **`sanitize_html`** — **field-by-field** semantics (same as `strip_images`
  and `excerpt_length`). Per-feed `nil` keeps the global default; any explicit
  value overrides it.

No changes to `Filters.merge/2` are needed — the existing `Map.merge/3` logic
already handles both conventions correctly.

## Section 3: Transform Order and Implementation

### Order

```
sanitize → strip_images → excerpt
```

Sanitization runs first so subsequent transformations operate on clean HTML.

### Implementation (private functions in `Exoplanet.Filters`)

**`apply_sanitization/2`**  
Guard-clauses on `sanitize_html: false` to skip entirely. Otherwise delegates
to `scrub_html/3` passing the `dropped_tags` and `dropped_attrs` from the
filter map.

**`scrub_html/3`**  
- `nil` and `""` pass through unchanged — preserves the `nil`-vs-`""` contract
  that `summary || body` fallbacks rely on.
- Non-empty binary: `LazyHTML.from_fragment → to_tree → scrub_node/3 on each
  node → from_tree → to_html`.

**`scrub_node/3`**  
- Tag in `dropped_tags` → return `[]` (entire subtree dropped).
- Other element tag → strip `dropped_attrs` from attrs, recurse into children.
- Comment node or text binary → pass through unchanged.

This mirrors `HtmlSanitizer.sanitize/1` exactly, parameterised by the filter
map instead of module attributes.

## Section 4: Planet BEAM Cleanup

After cutting an exoplanet release containing this change:

1. **Delete** `lib/planet_beam/blog/html_sanitizer.ex`.
2. **`lib/planet_beam/blog.ex`** — remove `alias PlanetBEAM.Blog.HtmlSanitizer`
   and the two `Map.update!(:body, …)` / `Map.update!(:summary, …)` calls in
   `store_in_persistent_term/2`. Posts from `Exoplanet.build/1` will already
   be sanitized.
3. **`mix.exs`** — remove `{:lazy_html, "~> 0.1"}` (becomes a transitive dep
   via exoplanet) and bump `{:exoplanet, "~> 0.4"}`.
4. **`mix.lock`** — run `mix deps.update exoplanet`.

No schema, controller, or template changes required.

## Section 5: Testing

### Exoplanet (`test/exoplanet/filters_test.exs`)

- `sanitize_html: true` (default) removes full subtrees of dropped tags
  (`iframe`, `script`, `object`, `embed`).
- `sanitize_html: true` strips `style` attributes from remaining elements.
- `sanitize_html: false` leaves content unchanged (opt-out path).
- Per-feed `dropped_tags` override replaces the default list (e.g. only
  `script`).
- `nil` and `""` body/summary pass through unchanged when sanitization is on.
- Sanitization runs before `strip_images`: a post whose body contains both an
  `<iframe>` and an `<img>` ends up with the iframe gone and the img replaced
  by a text link.

### Planet BEAM

Run `mix test` after removing `HtmlSanitizer` and bumping exoplanet. No new
tests required — behaviour is covered upstream.

## Files Affected

| File | Change |
|---|---|
| `lib/exoplanet/filters.ex` | Add 3 keys to `@type t`, new `apply_sanitization/2` + `scrub_html/3` + `scrub_node/3` private functions, wire into `transform/2` |
| `lib/exoplanet/config.ex` | Add 3 keys with defaults to `default_filters` in `defstruct` |
| `test/exoplanet/filters_test.exs` | New `describe "sanitize_html"` block (6 tests) |
| `CHANGELOG.md` | Entry under `[unreleased]` |
| `planet_beam/lib/planet_beam/blog/html_sanitizer.ex` | Delete |
| `planet_beam/lib/planet_beam/blog.ex` | Remove alias + 2 `Map.update!` calls |
| `planet_beam/mix.exs` | Remove `lazy_html`, bump `exoplanet` |

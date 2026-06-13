# Split `Exoplanet.Parser` into a fetcher and a pure parser

**Date:** 2026-06-13
**Issue:** #24 (follow-up from the project-wide review in #23)
**Status:** Approved

## Problem

`lib/exoplanet/parser.ex` (425 lines) currently does three distinct jobs:

1. **HTTP + conditional-GET caching** — `Req.get`, `Exoplanet.Cache` interaction
   (conditional headers, `put`/`get`, `on_success`/`on_error` notifications),
   `req_options` resolution + legacy-key deprecation warning.
2. **RSS/Atom format detection + XML extraction** — `rss_body?`, `parse_rss`,
   `parse_atom`, FastRSS calls.
3. **Field normalization** — author/category/date cleaning, id selection,
   `content:encoded` preference.

Because fetching and parsing are entangled, every parser test must go through
`Req.Test` stubs even when it only wants to assert on parsed `Post` fields.

## Goal

Extract an `Exoplanet.Fetcher` that owns jobs (1) — HTTP + `Exoplanet.Cache` —
leaving `Exoplanet.Parser` as a pure `body -> [Post]` function (jobs 2 and 3).
This makes the parser unit-testable without `Req.Test` stubs and gives the cache
logic its own focused test file.

The library's public API (`Exoplanet.build/1`) is unchanged. This is purely an
internal restructuring; behavior is preserved.

## Design

### `Exoplanet.Fetcher` (new, `@moduledoc false`)

Owns all HTTP + `Exoplanet.Cache` interaction.

- **Public:** `fetch(url, config) :: String.t() | nil` — the current
  `fetch_body/2`, renamed. Returns the body string, or `nil` on an uncached
  error (same semantics as today).
- **Moved verbatim from Parser** (private): `req_options`,
  `warn_legacy_req_options`, `cache_adapter`, `maybe_notify_success`,
  `maybe_notify_error`, `maybe_call_adapter`, `build_conditional_headers`,
  `maybe_update_cache`, `get_response_header`, `merge_headers`, `prepend_if`.
- The `:persistent_term` latch key for the one-time legacy-`req_options`
  warning moves from `{Exoplanet.Parser, :legacy_req_options_warned}` to
  `{Exoplanet.Fetcher, :legacy_req_options_warned}`.
- `require Logger`; depends on `Req` and the `Exoplanet.Cache` behaviour.

### `Exoplanet.Parser` (stays `@moduledoc false`)

Pure `body -> [Post]`.

- **Public:** `parse(body, url, name) :: [Exoplanet.Post.t()]` with a
  `when is_binary(body)` guard. No `nil` clause — the orchestrator guards
  against a failed fetch before calling. `url` is used for `Post.feed_url` and
  log context; `name` is the author fallback.
- **Keeps** (private): `rss_body?`, `parse_rss`, `parse_atom`, `log_parse_error`,
  `rss_published`, `denull_atom_updated`, `atom_post_id`, `parse_naive_datetime`,
  `clean_categories`, `clean_category`, `normalize_authors`, `rss_authors`,
  `blank_to_nil`, `blank?`.
- No longer references `Req`. Keeps `require Logger` (parse-error and
  unparseable-date warnings).

### `Exoplanet.build_source/3` (orchestrator)

Wires the two modules together and handles the `nil` (fetch-failed) case so the
parser only ever receives a real binary:

```elixir
defp build_source({url, attrs}, defaults, config) do
  filters = Exoplanet.Filters.merge(defaults, attrs[:filters])

  case Exoplanet.Fetcher.fetch(url, config) do
    nil ->
      []

    body ->
      body
      |> Exoplanet.Parser.parse(url, attrs.name)
      |> Exoplanet.Filters.apply(filters)
      |> sort_by_published_desc()
      |> Enum.take(config.new_feed_items)
  end
end
```

(`name` is a required source key, so `attrs.name` is safe — matching the current
`{url, %{name: name}}` match in `Parser.parse/2`.)

## Testing

### Mechanical stub-key rename (`Exoplanet.Parser` → `Exoplanet.Fetcher`)

The `Req.Test` plug name is just a label; it must match between the `:plug`
option and the `Req.Test.stub/2` call. Since HTTP now lives in the Fetcher, the
label is renamed for clarity:

- `test/test_helper.exs`: `plug: {Req.Test, Exoplanet.Fetcher}`.
- `test/support/test_helpers.ex`: stub key + doc strings → `Exoplanet.Fetcher`.
- `test/exoplanet_test.exs`: all `Req.Test.stub(Exoplanet.Parser, ...)` →
  `Exoplanet.Fetcher`.

### Cache tests → Fetcher

- Rename `test/exoplanet/parser_cache_test.exs` →
  `test/exoplanet/fetcher_cache_test.exs`, module `Exoplanet.FetcherCacheTest`,
  stub keys updated to `Exoplanet.Fetcher`. This becomes the cache logic's
  focused test file (its subject now lives in `Exoplanet.Fetcher`).

### `req_options_test.exs`

- Update the persistent_term erase key to
  `{Exoplanet.Fetcher, :legacy_req_options_warned}` and any stub key.

### New `test/exoplanet/parser_test.exs` (the coverage the split unlocks)

Pure tests that call `Parser.parse(fixture(:rss), url, name)` directly with a
fixture body and **no `Req.Test` stub**. Written test-first (TDD). Covers:

- RSS vs Atom detection (`rss.xml`, `rss1.xml`, `rss_no_version.xml`, `atom.xml`).
- `<content:encoded>` preferred over `<description>`
  (`rss_with_content_encoded.xml`).
- Dateless-entry skipping (`atom_published_missing.xml`, `rss_bad_date.xml`).
- Category cleaning (`*_with_categories.xml`,
  `atom_with_trailing_comma_categories.xml`).
- Author fallback to the source `name` when entry authors are blank.
- Post field mapping (`feed_url`, `id`, `title`, `published`, `summary`).

The existing suite (now pointed at `Exoplanet.Fetcher`) is the regression net for
behavior preservation; `parser_test.exs` is the genuinely new coverage.

## Documentation

- Update the `Exoplanet.Parser` bullet in `CLAUDE.md`'s Architecture section
  (it is no longer "purely HTTP fetch + XML parse") and add an
  `Exoplanet.Fetcher` bullet describing the HTTP + cache responsibility. Update
  the pipeline line if needed.
- No `README.md` / public-API change — `Exoplanet.build/1` is untouched.

## Out of scope

Everything else in issue #24 (sanitizer hardening, OSS hygiene files, Credo/
Dialyzer, `rss_body?` root-element check, timezone-loss docs). This spec is the
"highest-value structural refactor" item only.

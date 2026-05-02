# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Exoplanet is an Elixir library that aggregates multiple RSS and Atom feeds into a single unified feed, sorted by publication date (descending). Inspired by Planet Venus and NimblePublisher.

## Build & Test Commands

```bash
mix deps.get          # Fetch dependencies
mix compile           # Compile
mix test              # Run all tests
mix test test/exoplanet_test.exs           # Run a single test file
mix test test/exoplanet_test.exs:6         # Run a specific test (line number)
mix format            # Format code
mix format --check-formatted  # Check formatting without modifying
```

## Architecture

The pipeline flows: **Config → Parser (per source) → Post → Filters → sorted list**.

- `Exoplanet.build/1` is the main entry point — takes a `Config` struct, fetches and parses feeds concurrently via `Task.async_stream`, applies per-source filters, caps each source at `new_feed_items`, sorts the merged list by `published` (descending; `nil` sorts to the end), and takes the top `items`.
- `Exoplanet.Config` — struct with feed sources and settings. Loaded from a `.exs` file via `Config.from_file/1` (see `example/planet_beam.exs`). Required: `sources` (a map of `feed_url => %{name: "Author"}` plus optional per-feed keys: `homepage`, `language`, `filters`). Optional config keys: `default_filters`, `new_feed_items`, `feed_timeout`, `items`. Unknown keys raise on `from_file/1`.
- `Exoplanet.Parser` — purely HTTP fetch + XML parse. Returns built `%Post{}` structs for one source at a time; orchestration and filtering happen in `Exoplanet.build/1`. Detects RSS vs Atom via `rss_body?/1`: RSS if the body contains `<rss` or `<rdf:RDF` (covers RSS 2.0, RSS without version attribute, and RSS 1.0); otherwise treats as Atom. RSS bodies prefer `<content:encoded>` (Content RSS module) over `<description>` so Medium-style feeds render correctly. RSS dates use the custom `DateTimeParser`; Atom dates use `NaiveDateTime.from_iso8601/1`. An unparseable date in one entry logs a warning and skips that post — sibling posts in the same feed are still parsed. Blank authors/summaries are normalised to fall back to the source's `name` and `nil` respectively.
- `Exoplanet.Filters` — `merge/2` produces an effective filter map by overlaying per-feed `filters:` onto `default_filters` (per-feed `nil` keeps the default; per-feed lists for `allow_categories` / `block_categories` REPLACE the defaults rather than union). `apply/2` operates on a list of `Post` structs: drops by category allow/block, optionally rewrites `<img>` tags to text links (`strip_images`), and generates an HTML-escaped truncated `summary` (`excerpt_length`) without modifying `body`.
- `Exoplanet.DateTimeParser` — NimbleParsec-based RFC 822 date parser. **The `.ex.exs` file is the source definition; the `.ex` file is generated output and is committed because `nimble_parsec` is dev/test only — edit the `.ex.exs` file and recompile to regenerate.** 2-digit years are normalised to 2000+offset. `parse/1` returns `{:ok, NaiveDateTime.t()} | {:error, ...}`; `parse!/1` raises `Exoplanet.ParseError` on invalid input.
- `Exoplanet.Post` — struct representing a feed entry (id, feed_url, authors, title, body, categories, published, updated, summary).
- `Exoplanet.Cache` — optional behaviour for HTTP caching. Implement `get/1` and `put/2`; `on_success/2` and `on_error/3` are optional callbacks. Activate by setting `Application.put_env(:exoplanet, :cache_adapter, MyAdapter)`. When a cache adapter is present, the parser adds `If-None-Match`/`If-Modified-Since` headers and falls back to the cached body on non-200 responses or network errors.

## Testing

Tests use `Req.Test.stub/2` to mock HTTP requests (configured in `test/test_helper.exs`), so no real network calls are made. The stub is keyed on `Exoplanet.Parser`. Feed XML fixtures are defined as private `feed/1` functions at the bottom of `test/exoplanet_test.exs`. Cache adapter tests use an in-process `Agent`-backed adapter defined inline in `test/exoplanet/parser_cache_test.exs`.

## Key Dependencies

- `req` — HTTP client
- `fast_rss` — native RSS/Atom XML parsing (NIF-based)
- `lazy_html` — DOM-aware HTML manipulation for `Exoplanet.Filters` (image stripping, plain-text extraction for excerpts)
- `nimble_parsec` — parser combinator (dev only, for generating `DateTimeParser`)

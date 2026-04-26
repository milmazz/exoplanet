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

The pipeline flows: **Config → Parser → Post → sorted list**.

- `Exoplanet.build/1` is the main entry point — takes a `Config` struct, parses all feeds concurrently, builds `Post` structs, sorts by date (nil published dates sort to the earliest position), and takes the top N items.
- `Exoplanet.Config` — struct with feed sources and settings. Can be loaded from a config file (Elixir term format, see `examples/planet-beam.conf`). Sources is a map of URL → `%{name: "Author"}`.
- `Exoplanet.Parser` — fetches feeds concurrently via `Task.async_stream` + `Req`. Detects RSS vs Atom via `rss_body?/1`: RSS if the body contains `<rss` or `<rdf:RDF` (covers RSS 2.0, RSS without version attribute, and RSS 1.0); otherwise treats as Atom. RSS dates are parsed with the custom `DateTimeParser`; Atom dates use `NaiveDateTime.from_iso8601!/1`.
- `Exoplanet.DateTimeParser` — NimbleParsec-based RFC 822 date parser. **The `.ex.exs` file is the source definition; the `.ex` file is generated output — edit the `.ex.exs` file and recompile to regenerate.** 2-digit years are normalised to 2000+offset. Raises `Exoplanet.ParseError` on invalid input.
- `Exoplanet.Post` — struct representing a feed entry (id, feed_url, authors, title, body, categories, published, updated, summary).
- `Exoplanet.Cache` — optional behaviour for HTTP caching. Implement `get/1` and `put/2`; `on_success/2` and `on_error/3` are optional callbacks. Activate by setting `Application.put_env(:exoplanet, :cache_adapter, MyAdapter)`. When a cache adapter is present, the parser adds `If-None-Match`/`If-Modified-Since` headers and falls back to the cached body on non-200 responses or network errors.

## Testing

Tests use `Req.Test.stub/2` to mock HTTP requests (configured in `test/test_helper.exs`), so no real network calls are made. The stub is keyed on `Exoplanet.Parser`. Feed XML fixtures are defined as private `feed/1` functions at the bottom of `test/exoplanet_test.exs`. Cache adapter tests use an in-process `Agent`-backed adapter defined inline in `test/exoplanet/parser_cache_test.exs`.

## Key Dependencies

- `req` — HTTP client
- `fast_rss` — native RSS/Atom XML parsing (NIF-based)
- `nimble_parsec` — parser combinator (dev only, for generating `DateTimeParser`)

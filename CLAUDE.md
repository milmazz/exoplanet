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
mix precommit         # Run all CI checks locally (compile, format, deps.unlock, docs, test)
```

## Release Workflow

- Always run `mix precommit` before tagging releases.
- Verify referenced files/commands actually exist before adding them to README or docs (don't copy from a stale CLAUDE.md).

## Branching

- Never make edits directly on `main` — create a feature branch first.

## Superpowers Workflow

- Specs and plans created by the `superpowers` plugin (brainstorming → writing-plans) must land under the `.claude/` directory, not `docs/`: write specs to `.claude/specs/YYYY-MM-DD-<topic>-design.md` and plans to `.claude/plans/YYYY-MM-DD-<feature>.md`. These paths override the skills' `docs/superpowers/...` defaults.
- When a superpowers skill offers an implementation/execution approach (e.g. writing-plans' "Subagent-Driven vs Inline" choice), always choose the **Subagent-Driven** approach (`subagent-driven-development`).

## Implementation Discipline

### Behavior on Ambiguity

- When implementing parsing/validation logic with edge cases (e.g., unparseable dates, malformed XML), restate the agreed behavior before coding and confirm it matches the plan.

### Documentation Edits

- Before editing `README.md` or any user-facing docs, list every command, file, or target you plan to reference and verify each exists in the repo via `Bash`/`Read`. Show the verification output before writing.

## Architecture

The pipeline flows: **Config → Fetcher (HTTP+Cache) → Parser (per source) → Post → Filters → sorted list**.

- `Exoplanet.build/1` is the main entry point — takes a `Config` struct, fetches and parses feeds concurrently via `Task.async_stream` (`on_timeout: :kill_task`; a feed that exceeds `feed_timeout` + 1s grace is dropped with a logged warning, never crashing the build), applies per-source filters, caps each source at `new_feed_items`, sorts the merged list by `published` (descending; `nil` sorts to the end), and takes the top `items`.
- `Exoplanet.Config` — struct with feed sources and settings. Loaded from a `.exs` file via `Config.from_file/1` (see `example/planet_beam.exs`). Required: `sources` (a map of `feed_url => %{name: "Author"}` plus optional per-feed keys: `homepage`, `language`, `filters`). Optional config keys: `default_filters`, `new_feed_items`, `feed_timeout`, `items`. Unknown keys are ignored by `from_file/1` so one `.exs` file can also hold consumer-side settings.
- `Exoplanet.Fetcher` — HTTP fetch + `Exoplanet.Cache` interaction only. `fetch(url, config)` returns the body string or `nil` on an uncached error. HTTP requests use `feed_timeout` as Req's `:receive_timeout`; extra Req options come from the `:req_options` application env key (`:planet_req_options` is the deprecated fallback). When a cache adapter is present it adds `If-None-Match`/`If-Modified-Since` headers and falls back to the cached body on non-200 responses or network errors.
- `Exoplanet.Parser` — pure `parse(body, url, name) -> [Post]`. No HTTP; `Exoplanet.build_source/3` fetches first and only calls `parse/3` with a real binary body. Detects RSS vs Atom via `rss_body?/1` by inspecting only the first real element (the root), skipping the XML prolog, DOCTYPE, and comments: RSS if the root is `<rss>` or `<rdf:RDF>` (covers RSS 2.0, RSS without version attribute, and RSS 1.0); otherwise treats as Atom. Matching the root rather than any substring keeps a literal `<rss` inside an Atom entry's content from misfiring. RSS bodies prefer `<content:encoded>` (Content RSS module) over `<description>` so Medium-style feeds render correctly. RSS dates use the custom `DateTimeParser`; Atom dates use `NaiveDateTime.from_iso8601/1`. An entry without a usable date is skipped (RSS without `<pubDate>`, Atom without either `<published>` or `<updated>`); an unparseable date additionally logs a warning. In both cases sibling posts in the same feed are still parsed. Blank authors/summaries are normalised to fall back to the source's `name` and `nil` respectively.
- `Exoplanet.Filters` — `merge/2` produces an effective filter map by overlaying per-feed `filters:` onto `default_filters` (per-feed `nil` keeps the default; per-feed lists for `allow_categories` / `block_categories` REPLACE the defaults rather than union). `apply/2` operates on a list of `Post` structs: drops by category allow/block, sanitizes `body` HTML when `sanitize_html: true` (drops tags listed in `drop_tags` — the default denylist in `Exoplanet.Filters.defaults/0` covers script-bearing elements plus the SVG SMIL animation elements (`animate`/`set`/`animateTransform`/`animateMotion`), which can animate an ancestor's `href` to a `javascript:` URL —, attributes listed in `drop_attrs` — default `style` —, all `on*` event-handler attributes, and URL-bearing attributes (`href`, `src`, `srcset`, `action`, `formaction`, `poster`, `xlink:href`) whose URL scheme is not `http`/`https`/`mailto`; relative URLs are kept), optionally rewrites `<img>` tags to text links (`strip_images`), and generates an HTML-escaped truncated `summary` (`excerpt_length`) without modifying `body`. A configured `Exoplanet.Sanitizer` adapter replaces this built-in sanitizer.
- `Exoplanet.DateTimeParser` — NimbleParsec-based RFC 822 date parser. **The `.ex.exs` file is the source definition; the `.ex` file is generated output and is committed because `nimble_parsec` is dev/test only — edit the `.ex.exs` file, then regenerate with `mix nimble_parsec.compile lib/exoplanet/datetime_parser.ex.exs` and commit both files.** 4-digit years pass through unchanged; 2-digit years follow RFC 2822 §4.3 (00-49 → 2000s, 50-99 → 1900s). `parse/1` returns `{:ok, NaiveDateTime.t()} | {:error, reason}`; `parse!/1` raises `Exoplanet.ParseError` on invalid input.
- `Exoplanet.Post` — struct representing a feed entry (id, feed_url, authors, title, body, categories, published, updated, summary).
- `Exoplanet.Cache` — optional behaviour for HTTP caching. Implement `get/1` and `put/2`; `on_success/2` and `on_error/3` are optional callbacks. Activate by setting `Application.put_env(:exoplanet, :cache_adapter, MyAdapter)`. When a cache adapter is present, the fetcher adds `If-None-Match`/`If-Modified-Since` headers and falls back to the cached body on non-200 responses or network errors.
- `Exoplanet.Sanitizer` — optional behaviour for delegating HTML sanitization. Implement `sanitize/1` and activate with `Application.put_env(:exoplanet, :sanitizer_adapter, MyAdapter)` (or `config :exoplanet, sanitizer_adapter: ...`). When set and `sanitize_html` is `true`, the adapter replaces `Exoplanet.Filters`' built-in sanitize walk; `strip_images`/`excerpt_length` still apply afterward. `html_sanitize_ex` is the documented example adapter and is not a dependency.

## Testing

Tests use `Req.Test.stub/2` to mock HTTP requests (configured in `test/test_helper.exs`), so no real network calls are made. The stub is keyed on `Exoplanet.Fetcher`. Feed XML fixtures live in `test/support/fixtures/feeds/*.xml`, loaded via the `stub_feed/1` / `stub_feeds/1` helpers in `test/support/test_helpers.ex`. Cache adapter tests use in-process `Agent`-backed adapters defined inline in `test/exoplanet/fetcher_cache_test.exs`.

### Test Environment

- If tests fail in unexpected ways, check for stale NIF binaries (e.g., `fast_rss`) and rebuild deps with `mix deps.compile --force` before debugging further.

## Key Dependencies

- `req` — HTTP client
- `fast_rss` — native RSS/Atom XML parsing (NIF-based)
- `lazy_html` — DOM-aware HTML manipulation for `Exoplanet.Filters` (image stripping, plain-text extraction for excerpts)
- `nimble_parsec` — parser combinator (dev only, for generating `DateTimeParser`)

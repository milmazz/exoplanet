# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

### Fixed

- A single slow feed no longer crashes the entire build. `Exoplanet.build/1`
  now kills tasks that exceed `feed_timeout` (plus a 1s grace period) and
  drops only that feed, logging a warning that names the feed URL.
- `Exoplanet.DateTimeParser` no longer corrupts pre-2000 RFC 822 dates.
  Four-digit years pass through unchanged (1999 used to become 3999), and
  two-digit years follow the RFC 2822 century rule: 00-49 → 2000s, 50-99 →
  1900s ("99" used to become 2099).
- `Exoplanet.Parser` now ensures the cache adapter module is loaded before
  probing for the optional `on_success`/`on_error` callbacks, so they are no
  longer silently skipped in interactive/dev environments.

### Security

- The default HTML sanitizer (`sanitize_html: true`) now also removes `on*`
  event-handler attributes and URL-bearing attributes (`href`, `src`,
  `srcset`, `action`, `formaction`, `poster`, `xlink:href`) whose URL
  scheme is not `http`, `https`, or `mailto` (relative URLs are kept).
  Previously `javascript:` links and inline event handlers passed through.

### Changed

- `feed_timeout` is now enforced at the HTTP layer as Req's
  `:receive_timeout` (it previously only bounded the surrounding task), and
  Req's automatic retries are now disabled by default — a retried request
  could never finish inside the task backstop anyway, and a prompt error
  return is what enables the cached-body fallback. Re-enable retries via
  `:req_options` if you need them.
- The application env key for extra Req options is now `:req_options`.
  The old `:planet_req_options` key keeps working as a deprecated fallback
  and logs a one-time deprecation warning.
- `Exoplanet.Config.from_file/1` and `Exoplanet.build/1` now share one
  canonical defaults-merge path (`Exoplanet.Filters.merge/2`); `nil` values
  in `default_filters` keep the library default in both entry points.
- `Exoplanet.DateTimeParser.parse/1` now always returns
  `{:ok, NaiveDateTime.t()}` or a two-element `{:error, reason}` tuple
  (it previously leaked NimbleParsec's six-element error tuple).

### Added

- `Exoplanet.Sanitizer` behaviour: optionally delegate HTML sanitization to a
  comprehensive library (e.g. `html_sanitize_ex`) via
  `config :exoplanet, sanitizer_adapter: MyAdapter`. When set, the adapter
  replaces the built-in sanitizer.
- `CONTRIBUTING.md` with development setup, test conventions, and the
  `DateTimeParser` regeneration workflow.

## [0.5.0] - 2026-05-09

### Added

- `Exoplanet.Filters` now accepts `allow_categories: :all` and
  `block_categories: :none` to express "no constraint" explicitly.
  Lists keep working unchanged; atoms are normalized to `[]` internally
  by both `Exoplanet.Filters.merge/2` and
  `Exoplanet.Config.from_file/1`, so the struct's `default_filters`
  field is always in canonical list form. Invalid atoms
  (`allow_categories: :none`, `block_categories: :all`, or any
  unrecognized atom) raise `ArgumentError` at config-load / merge time.
  The `Exoplanet.Filters.t()` typespec is widened accordingly.

### Fixed

- `Exoplanet.build/1` now sorts each feed's entries by `published`
  (descending) before applying the per-feed `new_feed_items` cap.
  Previously the first N entries in document order were kept, so feeds
  that don't list newest-first (some Bridgetown / Jekyll templates,
  podcast feeds) had genuinely recent posts dropped before the global
  merge.
- The feed parser now trims trailing `,` / `;` and surrounding
  whitespace from feed categories at extraction time. Some Atom feeds
  emit terms like `otp,` (apparent producer-side templating bug) which
  silently failed `Exoplanet.Filters.passes_allowlist?` against the
  canonical `otp` allow-list entry, dropping the post.
- The Atom parser now derives `Exoplanet.Post.id` from the entry's
  `<link rel="alternate">` (or any `<link>` without a `rel`, per
  RFC 4287 §4.2.7.2) before falling back to `<id>`. Bridgetown-style
  feeds emit `<id>repo://posts.collection/_posts/...md</id>` and the
  canonical web URL only lives in `<link rel="alternate">`; consumers
  were rendering the `repo://` URN as a clickable link.

## [0.4.1] - 2026-05-06

### Fixed

- `Exoplanet.build/1` no longer raises `KeyError` when a partial
  `default_filters` map is supplied via direct struct construction (e.g.
  `%Exoplanet.Config{default_filters: %{allow_categories: [...]}}`). Missing
  keys are now filled in from `Exoplanet.Filters.defaults/0`. The
  `Exoplanet.Config.from_file/1` path was already unaffected.

## [0.4.0] - 2026-05-06

### Added

- The RSS parser now reads `<dc:creator>` (Dublin Core) when populating
  `Exoplanet.Post.authors`, preferring it over the RSS 2.0 `<author>`
  element. RSS spec'd `<author>` as an email, which most blogs leave empty;
  `<dc:creator>` is where the human-readable name typically lives.
- `Exoplanet.Filters` now sanitizes post bodies and summaries by default.
  Dangerous tags (`iframe`, `script`, `object`, `embed`, `style`, `base`) are
  removed entirely; `style` attributes are stripped from all remaining
  elements. Three new filter keys control the behaviour: `sanitize_html`
  (default `true`), `drop_tags` (default
  `~w(iframe script object embed style base)`), and `drop_attrs` (default
  `~w(style)`). All three follow the same per-feed override semantics as
  existing filter keys. Set `sanitize_html: false` per feed to opt out.
- `Exoplanet.Config.from_file/1` now merges user-supplied `default_filters` onto the
  built-in defaults, so config files that specify only a subset of filter keys
  receive the remaining defaults automatically. Existing config files require
  no changes.

## [0.3.0] - 2026-05-02

### Added

- `Exoplanet.Cache` behaviour gains two optional callbacks: `on_success/2` (called
  after a successful feed fetch that updates the cache) and `on_error/3` (called when
  a feed fetch fails and the cache is used as a fallback).
- `Exoplanet.Post` gains three new fields: `feed_url` (the source feed URL),
  `categories` (list of tag/category strings), and `summary` (optional post summary).
- `Exoplanet.Post` gains an `updated` field; the Atom parser falls back to `updated`
  when `published` is absent.
- `Exoplanet.Config` accepts a `default_filters` field (default: empty filter map)
  describing global content filters: `allow_categories`, `block_categories`,
  `strip_images`, `excerpt_length`.
- `Exoplanet.Filters` module with `merge/2` and `apply/2`. Per-feed filters
  inside the `sources` map merge with `default_filters`; `allow_categories` and
  `block_categories` replace defaults rather than union, all other keys merge
  field-by-field.
- `Exoplanet.build/1` applies merged filters to each source's posts before
  truncating to `new_feed_items` (filtering happens before the per-feed cap).
- `:lazy_html` dependency for HTML manipulation in filters.

### Changed

- The internal Exoplanet.Parser module is now purely HTTP fetch + XML parse;
  it returns built `%Exoplanet.Post{}` structs. Per-source filtering and the
  `new_feed_items` cap moved to `Exoplanet.build/1`.
- Renamed `examples/planet-beam.conf` to `example/planet_beam.exs` to make it
  explicit that the file is an Elixir script.

### Fixed

- A single RSS entry with a malformed `<pubDate>` no longer crashes the entire
  feed's parse. The offending entry is skipped (siblings in the same feed are
  still emitted) and a warning is logged with the feed URL and offending value.
  Atom `<published>` / `<updated>` fields are still rejected upstream by
  `FastRSS`, but the parser no longer uses bang variants and so will degrade
  gracefully if that ever changes.
- Entries without a usable date are now also skipped: RSS items missing
  `<pubDate>` (and Dublin Core `<dc:date>`) and Atom entries missing both
  `<published>` and `<updated>`. Without a date these posts can't participate
  in the chronological merge, so the previous behaviour (keep with `nil`
  published, sort to the end) was rarely useful.
- RSS 1.0 / RDF feeds now sort correctly: when `<pubDate>` is absent, the
  parser falls back to the first Dublin Core `<dc:date>` value (an ISO-8601
  string in `FastRSS`'s `dublin_core_ext.dates`). Previously these entries
  were emitted with `published: nil` and bunched at the end of the list.

- RSS detection now recognises feeds that omit the `version` attribute on `<rss>` and
  RSS 1.0 feeds that use the `<rdf:RDF>` root element. Previously these were
  mistakenly parsed as Atom.
- Sorting posts no longer crashes when a post has a `nil` published date; such posts
  are sorted to the end of the list.
- Cache lookup on a 304 Not Modified response no longer raises when the cached entry
  is `nil`.
- Empty `categories` values in both Atom and RSS feeds are normalised to `nil` instead
  of being returned as empty strings or nested lists.
- Generated excerpts are HTML-escaped before being stored in `summary`, so consumers
  can render them with `raw/1` without breaking layout. Previously, decoded `<` from
  `<pre>` code samples would be re-interpreted as real elements.
- Blank/whitespace-only `<author>` (RSS) and `<author><name></name></author>` (Atom)
  values now fall back to the source's configured `name`. Previously the empty string
  bypassed `||` fallbacks because empty strings are truthy in Elixir.
- Empty `<summary>` elements are normalised to `nil` so consumers' `summary || body`
  fallback works.
- RSS `<content:encoded>` (Content RSS module) is now preferred over `<description>`
  for the post body. Feeds like Medium put the full HTML article in `content:encoded`
  and leave `description` short or empty.

### Removed

- **Breaking:** `Exoplanet.Config` no longer holds site-presentation metadata.
  The library now only owns fields it actually reads in `Exoplanet.build/1`:
  `sources`, `default_filters`, `new_feed_items`, `feed_timeout`, `items`. The
  removed fields — `name`, `link`, `owner_name`, `owner_email`, `about`,
  `code_of_conduct`, `activity_threshold`, `related_sites` — were never used
  by exoplanet itself; they belong to the consumer (e.g. `planet_beam`).
  `Exoplanet.Config.from_file/1` now ignores unknown keys, so a single `.exs`
  file can still serve both exoplanet and a consumer-side config struct.
- Vestigial `Exoplanet.Config` fields that were never wired up: `cache_directory`,
  `output_dir`, `output_theme`, `log_level`. They were carried over from Venus's
  static-output workflow and never had any effect. Configs that still set them are
  silently ignored (per the unknown-keys rule above), but the values are no longer
  surfaced anywhere — remove them from your config file at your convenience.

## [0.2.0] - 2025-03-31

### Added

- Initial CHANGELOG file.
- Allow to specify the `about` and `releated_sites` via configuration.
- Custom date time parser for RSS. Given that [RSS spec](https://www.rssboard.org/rss-specification)
  says that all dates in RSS conform to the Date and Time Specification
  of [RFC 822](http://asg.web.cmu.edu/rfc/rfc822.html), with the exception
  that the year may be expressed with two characters or four
  characters (four preferred).

### Changed

- Raise an exception if the any publication date cannot be parsed.

### Removed

- Unused dependencies, such as `timex`.

## [0.1.0] - 2025-04-25

### Added

- Initial release.

[unreleased]: https://github.com/milmazz/exoplanet/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/milmazz/exoplanet/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/milmazz/exoplanet/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/milmazz/exoplanet/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/milmazz/exoplanet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/milmazz/exoplanet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/milmazz/exoplanet/releases/tag/v0.1.0

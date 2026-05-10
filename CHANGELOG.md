# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

### Added

- `Exoplanet.Filters` now accepts `allow_categories: :all` and
  `block_categories: :none` to express "no constraint" explicitly.
  Lists keep working unchanged; atoms are normalized to `[]` internally.
  Invalid atoms (`allow_categories: :none`, `block_categories: :all`, or
  any unrecognized atom) raise `ArgumentError` at config-load / merge
  time. The `Exoplanet.Filters.t()` typespec is widened accordingly.

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

[unreleased]: https://github.com/milmazz/exoplanet/compare/v0.4.1...HEAD
[0.4.1]: https://github.com/milmazz/exoplanet/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/milmazz/exoplanet/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/milmazz/exoplanet/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/milmazz/exoplanet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/milmazz/exoplanet/releases/tag/v0.1.0

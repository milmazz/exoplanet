# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

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

- `Exoplanet.Parser.parse/2` is now purely HTTP fetch + XML parse; it returns
  built `%Exoplanet.Post{}` structs. Per-source filtering and the `new_feed_items`
  cap moved to `Exoplanet.build/1`.

### Fixed

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
  static-output workflow and never had any effect. Configs that still set these keys
  will now raise on `Config.from_file/1` — remove them from your config file.

## [0.2.0] - 2025-04-31

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

[unreleased]: https://github.com/milmazz/exoplanet/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/milmazz/exoplanet/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/milmazz/exoplanet/releases/tag/v0.1.0

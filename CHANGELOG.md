# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

### Added

- `Exoplanet.Config` now accepts a `code_of_conduct` field (defaults to `""`).
- `Exoplanet.Cache` behaviour gains two optional callbacks: `on_success/2` (called
  after a successful feed fetch that updates the cache) and `on_error/3` (called when
  a feed fetch fails and the cache is used as a fallback).
- `Exoplanet.Post` gains three new fields: `feed_url` (the source feed URL),
  `categories` (list of tag/category strings), and `summary` (optional post summary).
- `Exoplanet.Post` gains an `updated` field; the Atom parser falls back to `updated`
  when `published` is absent.

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

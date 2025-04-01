# CHANGELOG

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-04-31

### Added

* Initial CHANGELOG file.
* Allow to specify the `about` and `releated_sites` via configuration.
* Custom date time parser for RSS. Given that [RSS spec](https://www.rssboard.org/rss-specification)
  says that all dates in RSS conform to the Date and Time Specification
  of [RFC 822](http://asg.web.cmu.edu/rfc/rfc822.html), with the exception
  that the year may be expressed with two characters or four
  characters (four preferred).

### Changed

* Raise an exception if the any publication date cannot be parsed.

### Removed

* Unused dependencies, such as `timex`.

## [0.1.0] - 2025-04-25

### Added

* Initial release.

[0.2.0]: https://github.com/milmazz/exoplanet/releases/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/milmazz/exoplanet/releases/tag/v0.1.0

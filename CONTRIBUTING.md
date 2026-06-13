# Contributing to Exoplanet

Thanks for your interest in improving Exoplanet! This document explains how
to set up a development environment, run the checks that CI runs, and get a
change merged.

## Getting started

You need Elixir `~> 1.17` and a compatible OTP release (CI tests Elixir
1.17–1.19 on OTP 27–28; see `.github/workflows/elixir.yml`).

```bash
git clone https://github.com/milmazz/exoplanet.git
cd exoplanet
mix deps.get
mix test
```

Some dependencies (`fast_rss`, `lazy_html`) are NIF-based. If tests fail in
unexpected ways after switching Elixir/OTP versions, rebuild them:

```bash
mix deps.compile --force
```

## Running the checks

Run the full CI suite locally before opening a pull request:

```bash
mix precommit
```

This runs, in order: `compile --warnings-as-errors`, `format
--check-formatted`, `deps.unlock --check-unused`, `docs --warnings-as-errors`,
and `test`.

## Project layout

The pipeline flows **Config → Parser (per source) → Post → Filters → sorted
list**:

| Module | Responsibility |
|---|---|
| `Exoplanet` | Entry point: fetches feeds concurrently, filters, sorts, caps |
| `Exoplanet.Config` | Configuration struct; loaded from an `.exs` file |
| `Exoplanet.Parser` | HTTP fetch + RSS/Atom XML parsing into `Post` structs |
| `Exoplanet.Post` | One feed entry |
| `Exoplanet.Filters` | Category allow/block, HTML sanitization, excerpts |
| `Exoplanet.DateTimeParser` | RFC 822 date parser (generated, see below) |
| `Exoplanet.Cache` | Optional behaviour for HTTP conditional-GET caching |

See `example/planet_beam.exs` for a config file that
exercises every supported field.

## Testing

Tests never hit the network. HTTP requests are stubbed with
[`Req.Test`](https://hexdocs.pm/req/Req.Test.html), wired up in
`test/test_helper.exs` and keyed on `Exoplanet.Parser`.

- Feed XML fixtures live in `test/support/fixtures/feeds/*.xml`.
- `test/support/test_helpers.ex` provides
  `stub_feed/1` (one fixture for every request) and `stub_feeds/1`
  (dispatch by host) helpers.
- Cache adapter tests use in-process `Agent`-backed adapters defined inline
  in `test/exoplanet/parser_cache_test.exs`.

When fixing a bug, please add a regression test that documents the bug it
guards against — see the existing tests for the style.

```bash
mix test                              # everything
mix test test/exoplanet_test.exs      # one file
mix test test/exoplanet_test.exs:42   # one test, by line number
```

## The generated DateTimeParser

`lib/exoplanet/datetime_parser.ex` is **generated output — do not edit it
directly**. The source definition is `lib/exoplanet/datetime_parser.ex.exs`
(a NimbleParsec parser). The generated file is committed because
`nimble_parsec` is a dev/test-only dependency.

To change date parsing:

1. Edit `lib/exoplanet/datetime_parser.ex.exs`.
2. Regenerate the committed file:

   ```bash
   mix nimble_parsec.compile lib/exoplanet/datetime_parser.ex.exs
   ```

3. Run `mix test` and commit **both** files together.

## Submitting changes

1. Fork the repository and create a feature branch from `main` — never
   commit directly to `main`.
2. Make your change, with tests.
3. Run `mix precommit`.
4. Open a pull request with a clear description of the problem and the
   solution. Reference any related issue.
5. Update the `[unreleased]` section of `CHANGELOG.md` when
   the change is user-visible (the file follows
   [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

For larger changes (new filter types, parser rework, new behaviours),
please open an issue first so the design can be discussed before you invest
time in an implementation.

## Reporting issues

Open a [GitHub issue](https://github.com/milmazz/exoplanet/issues) with:

- What you expected and what happened instead.
- The feed URL or a minimal XML snippet that reproduces the problem, when
  the issue is feed-specific.
- Elixir/OTP versions and the Exoplanet version.

If you believe you have found a security-sensitive problem (for example in
the HTML sanitizer), please email the maintainer privately instead of
opening a public issue — see the maintainer contact on the
[Hex package page](https://hex.pm/packages/exoplanet).

## License

By contributing, you agree that your contributions will be licensed under
the Apache-2.0 license (see `LICENSE`).

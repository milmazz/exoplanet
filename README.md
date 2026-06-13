# Exoplanet

Exoplanet is an Elixir library that aggregates multiple RSS and Atom feeds
into a single, unified feed sorted by publication date (descending).

It downloads each source concurrently, applies optional per-feed content
filters (category allow/block lists, image stripping, summary excerpts),
caps the contribution from any one feed, and returns a flat list of
`%Exoplanet.Post{}` structs ready to render.

Inspired by [Planet Venus](https://github.com/rubys/venus) and
[NimblePublisher](https://github.com/dashbitco/nimble_publisher).

## Installation

Add `:exoplanet` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:exoplanet, "~> 0.6"}
  ]
end
```

Documentation is published at <https://hexdocs.pm/exoplanet>.

## Quick start

Describe your feeds in an `.exs` file that returns a map:

```elixir
# planet.exs
%{
  items: 60,
  new_feed_items: 4,
  default_filters: %{
    allow_categories: ["elixir", "erlang"],
    block_categories: [],
    strip_images: false,
    excerpt_length: nil,
    sanitize_html: true
    # `drop_tags` / `drop_attrs` are omitted so they inherit the secure
    # built-in defaults — see `Exoplanet.Filters` to customize them.
  },
  sources: %{
    "https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"},
    "https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}
  }
}
```

Load it and build the merged feed:

```elixir
config = Exoplanet.Config.from_file("planet.exs")
posts  = Exoplanet.build(config)
```

`posts` is a list of `Exoplanet.Post` structs sorted newest-first. See
[example/planet_beam.exs](example/planet_beam.exs) for a fuller config that
exercises the supported fields (it leaves `drop_tags` / `drop_attrs` at
their secure defaults), and `Exoplanet.Filters` for the filter semantics.

### A note on ordering and time zones

`Post.published`/`Post.updated` are `NaiveDateTime` values, and the merged feed
is sorted by `published` descending. Both date paths discard the original UTC
offset: RSS dates go through `Exoplanet.DateTimeParser` (RFC 822) and Atom dates
through `NaiveDateTime.from_iso8601/1`, neither of which keeps the zone. This is
a deliberate trade-off — feeds publish in many zones, and Exoplanet treats every
timestamp as wall-clock time.

The practical consequence: when two posts from feeds in different zones are
published close together, their *relative* order can be off by as much as the
offset difference (up to ~24h). For a human-readable aggregated feed this is
usually fine; if you need globally-correct chronological ordering, normalise the
timestamps to UTC yourself before relying on the order.

### A note on HTML sanitization

With `sanitize_html: true` (the default), Exoplanet removes the tags in
`drop_tags`, the attributes in `drop_attrs`, all `on*` event-handler
attributes, and any URL-bearing attribute (`href`, `src`, `srcset`, `action`,
`formaction`, `poster`, `xlink:href`) whose URL scheme is not `http`,
`https`, or `mailto`. This is defense-in-depth for feed content, not a
guarantee — if you render feed HTML in a security-sensitive context,
consider pairing it with a dedicated sanitizer such as
[html_sanitize_ex](https://hex.pm/packages/html_sanitize_ex).

To delegate sanitization to such a library, implement the
`Exoplanet.Sanitizer` behaviour and configure it:

```elixir
defmodule MyApp.FeedSanitizer do
  @behaviour Exoplanet.Sanitizer

  @impl true
  def sanitize(html), do: HtmlSanitizeEx.basic_html(html)
end
```

```elixir
# config/config.exs
config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer
```

When configured (and `sanitize_html` is `true`), the adapter **replaces** the
built-in sanitizer. `html_sanitize_ex` is not a dependency of Exoplanet — add
it to your own application.

Note that `Exoplanet.Config.from_file/1` evaluates the config file with
`Code.eval_file/1` — treat that file as trusted code, like any other `.exs`
in your project.

## HTTP client options

Each feed request is bounded by the config's `feed_timeout` (seconds), which
is passed to [Req](https://hexdocs.pm/req) as `:receive_timeout`. You can
forward additional options to `Req.get/2` (user-agent, proxy, retry policy,
…) via the application environment:

```elixir
Application.put_env(:exoplanet, :req_options, headers: [user_agent: "my-planet/1.0"])
```

The old key name `:planet_req_options` still works but is deprecated; use
`:req_options`.

## HTTP caching (optional)

Exoplanet can issue conditional `If-None-Match` / `If-Modified-Since`
requests and fall back to a cached body on transient errors. Implement
the `Exoplanet.Cache` behaviour and register the adapter:

```elixir
Application.put_env(:exoplanet, :cache_adapter, MyApp.FeedCache)
```

See the `Exoplanet.Cache` module docs for the callback contract and the
optional `on_success/2` / `on_error/3` notification hooks.

## Migration from 0.2.x

`Exoplanet.Config` was slimmed down in 0.3.0 to hold only fields the
library itself reads. Site-presentation metadata (`name`, `link`,
`owner_name`, `owner_email`, `about`, `code_of_conduct`,
`activity_threshold`, `related_sites`) and vestigial Venus-era settings
(`cache_directory`, `output_dir`, `output_theme`, `log_level`) are no
longer part of the struct.

`Exoplanet.Config.from_file/1` ignores keys it doesn't recognise, so a single
`.exs` file can still serve both Exoplanet and a consumer-side config
(for example a static-site generator) — keep the extra fields in the
same map and read them yourself.

See the [CHANGELOG](CHANGELOG.md) for the full list of changes.

## Contributing

Contributions are welcome! See
[CONTRIBUTING.md](https://github.com/milmazz/exoplanet/blob/main/CONTRIBUTING.md)
for development setup, the test conventions, and how the generated
`DateTimeParser` is regenerated. Run `mix precommit` before opening a pull
request — it mirrors the CI checks.

## License

Apache-2.0. See [LICENSE](https://github.com/milmazz/exoplanet/blob/main/LICENSE).

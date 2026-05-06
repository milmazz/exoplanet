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
    {:exoplanet, "~> 0.4"}
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
    sanitize_html: true,
    dropped_tags: ~w(iframe script object embed),
    dropped_attrs: ~w(style)
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
exercises every supported field, and `Exoplanet.Filters` for the filter
semantics.

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

## License

Apache-2.0. See [LICENSE](https://github.com/milmazz/exoplanet/blob/main/LICENSE).

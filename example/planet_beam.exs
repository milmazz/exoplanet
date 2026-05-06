%{
  # Optional: per-fetch HTTP timeout (seconds)
  feed_timeout: 20,

  # Optional: total post cap across all feeds (newest first)
  items: 60,

  # Optional: max posts kept per feed per rebuild — prevents one busy feed
  # from monopolising the output.
  new_feed_items: 4,

  # Optional: global content filters applied to every feed by exoplanet.
  # Per-feed `filters:` overrides on individual sources merge with these
  # defaults — see `Exoplanet.Filters`.
  default_filters: %{
    allow_categories: ["elixir", "erlang", "gleam", "otp", "beam"],
    block_categories: ["personal", "food", "travel"],
    strip_images: false,
    excerpt_length: nil,
    sanitize_html: true,
    drop_tags: ~w(iframe script object embed style base),
    drop_attrs: ~w(style)
  },

  # Required: feed sources. Each entry can carry optional metadata that
  # consumers (e.g. planet_beam) may use:
  #   * `homepage`  — author's blog URL (sidebar link target)
  #   * `language`  — BCP-47 tag (emitted as `xml:lang` in OPML output)
  #   * `filters`   — per-feed override of `default_filters` above
  sources: %{
    "https://milmazz.uno/atom.xml" => %{
      name: "Milton Mazzarri",
      homepage: "https://milmazz.uno",
      language: "en"
    },
    "https://www.theerlangelist.com/rss" => %{
      name: "Saša Jurić"
    }
  }
}

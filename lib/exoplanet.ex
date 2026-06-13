defmodule Exoplanet do
  @moduledoc """
  Exoplanet is a feed aggregator library that combines multiple RSS and Atom sources into a single, unified feed.

  Exoplanet downloads news feeds, following the RSS or Atom specs, and aggregates
  their content together into a single combined feed. The news will be ordered
  based on their publication date, in descending order.

  Exoplanet is inspired by [Planet Venus](https://github.com/rubys/venus), and [NimblePublisher](https://github.com/dashbitco/nimble_publisher). It provides a flexible and efficient way to aggregate content from various sources.

  This library is designed for developers who need to aggregate feeds in their applications.
  It provides a simple and efficient way to combine multiple feeds into one.
  """

  require Logger

  @doc """
  Returns a list of ordered post based on their publication date
  """
  @spec build(Exoplanet.Config.t()) :: [Exoplanet.Post.t()]
  def build(%Exoplanet.Config{sources: sources, default_filters: defaults} = config) do
    # Defensively fill missing keys from library defaults so direct struct
    # construction with a partial `default_filters` map doesn't crash later
    # in `Filters.apply/2`. `Config.from_file/1` already does this, so the
    # merge is a no-op for that path.
    defaults = Exoplanet.Filters.merge(Exoplanet.Filters.defaults(), defaults)

    # `ordered: true` (the default) keeps results aligned with `source_list`
    # so the zip below can name the feed in timeout warnings. It costs
    # nothing here: feeds still run concurrently and the merged list is
    # re-sorted anyway.
    source_list = Enum.to_list(sources)

    # `feed_timeout` bounds the HTTP request itself (`receive_timeout` in
    # `Exoplanet.Fetcher`); the task timeout adds a 1s grace period so the
    # HTTP timeout fires first and the fetcher can still fall back to a
    # cached body. The task kill is a backstop for anything else that hangs.
    source_list
    |> Task.async_stream(&build_source(&1, defaults, config),
      timeout: to_timeout(second: config.feed_timeout) + 1_000,
      on_timeout: :kill_task
    )
    |> Stream.zip(source_list)
    |> Stream.flat_map(fn
      {{:ok, posts}, _source} ->
        posts

      {{:exit, :timeout}, {url, _attrs}} ->
        Logger.warning(
          "Feed #{url}: dropped — did not finish within feed_timeout (#{config.feed_timeout}s)"
        )

        []

      {{:exit, reason}, {url, _attrs}} ->
        Logger.warning("Feed #{url}: dropped — task exited: #{inspect(reason)}")
        []
    end)
    |> sort_by_published_desc()
    |> Enum.take(config.items)
  end

  # Fetch, parse, filter, and cap a single source.
  defp build_source({url, attrs}, defaults, config) do
    filters = Exoplanet.Filters.merge(defaults, attrs[:filters])

    case Exoplanet.Fetcher.fetch(url, config) do
      nil ->
        []

      body ->
        body
        |> Exoplanet.Parser.parse(url, attrs.name)
        |> Exoplanet.Filters.apply(filters)
        # Sort each per-feed list by publication date (descending) before
        # capping with `new_feed_items`. Some feeds don't emit entries in
        # newest-first order; without this sort, document-order older
        # entries can crowd out the genuinely-recent ones.
        |> sort_by_published_desc()
        |> Enum.take(config.new_feed_items)
    end
  end

  # Newest first; posts without a date sort to the end via the year-0 sentinel.
  # Timestamps are NaiveDateTime (source UTC offsets are discarded upstream), so
  # cross-feed ordering is wall-clock and can be skewed by up to the offset
  # difference — see the "Time zones" section in `Exoplanet.Post`.
  defp sort_by_published_desc(posts) do
    Enum.sort_by(posts, &(&1.published || ~N[0000-01-01 00:00:00]), {:desc, NaiveDateTime})
  end
end

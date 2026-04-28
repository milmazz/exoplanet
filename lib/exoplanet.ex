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

  @doc """
  Returns a list of ordered post based on their publication date
  """
  def build(%Exoplanet.Config{sources: sources, default_filters: defaults} = config) do
    sources
    |> Task.async_stream(
      fn {_url, attrs} = source ->
        filters = Exoplanet.Filters.merge(defaults, attrs[:filters])

        source
        |> Exoplanet.Parser.parse(config)
        |> Exoplanet.Filters.apply(filters)
        |> Enum.take(config.new_feed_items)
      end,
      ordered: false,
      timeout: to_timeout(second: config.feed_timeout)
    )
    |> Stream.flat_map(fn
      {:ok, posts} -> posts
      _ -> []
    end)
    |> Enum.sort_by(&(&1.published || ~N[0000-01-01 00:00:00]), {:desc, NaiveDateTime})
    |> Enum.take(config.items)
  end
end

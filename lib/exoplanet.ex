defmodule Exoplanet do
  @moduledoc """
  Exoplanet is a feed aggregator library that combines multiple RSS and ATOM sources into a single, unified feed.

  Exoplanet downloads news feeds, following the RSS or ATOM specs, and aggregates
  their content together into a single combined feed. The news will be ordered
  based on their publication date, in descending order.

  Exoplanet is inspired by [Planet Venus](https://github.com/rubys/venus), and [NimblePublisher](https://github.com/dashbitco/nimble_publisher). It provides a flexible and efficient way to aggregate content from various sources.

  This library is designed for developers who need to aggregate feeds in their applications.
  It provides a simple and efficient way to combine multiple feeds into one.
  """

  @doc """
  Returns a list of ordered post based on their publication date
  """
  def build(%Exoplanet.Config{} = config) do
    config
    |> Exoplanet.Parser.parse()
    |> Stream.map(fn {attrs, body} -> Exoplanet.Post.build(attrs, body) end)
    |> Enum.sort_by(& &1.published, {:desc, Date})
    |> Enum.take(config.items)
  end
end

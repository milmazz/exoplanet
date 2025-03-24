defmodule Exoplanet do
  @moduledoc """
  Exoplanet is a feed aggregator, inspired by PlanetPlanet and Planet Venus.

  Exoplanet downloads news feeds, following the RSS or ATOM specs, and aggregates
  their content together into a single combined feed. The news will be ordered
  based on their publication date, in descending order.
  """

  @doc """
  Returns a list of ordered post based on their publication date
  """
  def build(%Exoplanet.Config{} = config) do
    config
    |> Exoplanet.Parser.parse()
    |> Stream.map(fn {attrs, body} -> Exoplanet.Post.build(attrs, body) end)
    |> Enum.sort_by(& &1.published, {:desc, Date})
  end
end

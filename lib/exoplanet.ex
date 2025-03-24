defmodule Exoplanet do
  def build(%Exoplanet.Config{} = config) do
    config
    |> Exoplanet.Parser.parse()
    |> Stream.map(fn {attrs, body} -> Exoplanet.Post.build(attrs, body) end)
    |> Enum.sort_by(& &1.published, {:desc, Date})
  end
end

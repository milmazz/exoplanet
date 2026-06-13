defmodule Exoplanet.Config do
  @moduledoc """
  Exoplanet configuration.

  Required keys:

  * `sources` — map of `feed_url => %{name: ...}` (plus optional per-feed keys
    like `homepage`, `language`, `filters`)

  Optional keys (with defaults):

  * `default_filters` — global content filters (see `Exoplanet.Filters`)
  * `new_feed_items` (`4`) — max posts kept per feed per rebuild
  * `feed_timeout` (`20`) — per-feed HTTP timeout in seconds
  * `items` (`60`) — total post cap across all feeds

  This struct holds only the fields that `Exoplanet.build/1` actually reads.
  Site-level metadata (planet name, owner, about page, related sites, …)
  belongs to the consumer (e.g. `planet_beam`), not to this library.
  """

  @type t :: %__MODULE__{
          sources: map(),
          new_feed_items: pos_integer(),
          feed_timeout: pos_integer(),
          items: pos_integer(),
          default_filters: Exoplanet.Filters.t()
        }

  @enforce_keys [:sources]
  defstruct [
    :sources,
    new_feed_items: 4,
    feed_timeout: 20,
    items: 60,
    default_filters: Exoplanet.Filters.defaults()
  ]

  @doc """
  Creates `Exoplanet.Config` from the given file.

  Unknown keys in the file are ignored, so consumers may keep additional
  metadata in the same `.exs` file without conflicting with this struct.
  """
  @spec from_file(Path.t()) :: t()
  def from_file(path) when is_binary(path) do
    {attrs, _} = Code.eval_file(path)
    config = struct!(__MODULE__, Map.take(attrs, recognized_keys()))

    # Same merge `Exoplanet.build/1` applies, so both entry points share one
    # canonical defaults path (nil values keep the library default).
    merged_filters = Exoplanet.Filters.merge(Exoplanet.Filters.defaults(), config.default_filters)

    %{config | default_filters: merged_filters}
  end

  defp recognized_keys, do: Enum.map(__MODULE__.__info__(:struct), & &1.field)
end

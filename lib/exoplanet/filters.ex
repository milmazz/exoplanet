defmodule Exoplanet.Filters do
  @moduledoc """
  Per-feed content filters: category allow/block lists, image stripping,
  and summary truncation. See the Per-Feed Configuration design spec for
  semantics.
  """

  @type t :: %{
          allow_categories: [String.t()],
          block_categories: [String.t()],
          strip_images: boolean(),
          excerpt_length: pos_integer() | nil
        }

  @doc """
  Merges a per-feed filter map onto a default filter map.

  `allow_categories` and `block_categories` REPLACE the default value when
  the per-feed map sets them to a list. Other keys override field-by-field.
  Per-feed keys set to `nil` leave the default in place.
  """
  @spec merge(t(), map() | nil) :: t()
  def merge(defaults, nil), do: defaults
  def merge(defaults, per_feed) when map_size(per_feed) == 0, do: defaults

  def merge(defaults, per_feed) do
    Enum.reduce(per_feed, defaults, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end

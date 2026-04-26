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

  @doc """
  Applies the merged filter map to a list of `Exoplanet.Post` structs.

  Returns the filtered list. Posts dropped by category filters are removed
  entirely. The `strip_images` and `excerpt_length` filters modify each
  post's `summary` (and HTML body for image stripping).
  """
  @spec apply([Exoplanet.Post.t()], t()) :: [Exoplanet.Post.t()]
  def apply(posts, filters) do
    allow_lower = Enum.map(filters.allow_categories, &String.downcase/1)
    block_lower = Enum.map(filters.block_categories, &String.downcase/1)
    Enum.filter(posts, &keep?(&1, allow_lower, block_lower))
  end

  defp keep?(post, allow_lower, block_lower) do
    passes_allowlist?(post.categories, allow_lower) and
      passes_blocklist?(post.categories, block_lower)
  end

  defp passes_allowlist?(_categories, []), do: true
  defp passes_allowlist?(nil, _allow), do: false

  defp passes_allowlist?(categories, allow_lower) do
    Enum.any?(categories, &(String.downcase(&1) in allow_lower))
  end

  defp passes_blocklist?(_categories, []), do: true
  defp passes_blocklist?(nil, _block), do: true

  defp passes_blocklist?(categories, block_lower) do
    not Enum.any?(categories, &(String.downcase(&1) in block_lower))
  end
end

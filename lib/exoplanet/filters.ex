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

    posts
    |> Enum.filter(&keep?(&1, allow_lower, block_lower))
    |> Enum.map(&transform(&1, filters))
  end

  defp transform(post, %{strip_images: true}) do
    post
    |> Map.update!(:body, &maybe_strip_images/1)
    |> Map.update!(:summary, &maybe_strip_images/1)
  end

  defp transform(post, _filters), do: post

  defp maybe_strip_images(nil), do: nil
  defp maybe_strip_images(""), do: ""

  defp maybe_strip_images(html) when is_binary(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> strip_images_tree()
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
  end

  defp strip_images_tree(tree) when is_list(tree) do
    Enum.flat_map(tree, &strip_images_node/1)
  end

  defp strip_images_node({"img", attrs, _children}) do
    alt = attr_value(attrs, "alt")
    src = attr_value(attrs, "src")
    image_replacement(alt, src)
  end

  defp strip_images_node({tag, attrs, children}) when is_binary(tag) do
    [{tag, attrs, strip_images_tree(children)}]
  end

  defp strip_images_node(other), do: [other]

  # Drop the image entirely when there's no alt text.
  defp image_replacement(nil, _src), do: []
  defp image_replacement("", _src), do: []
  # Plain text only when there's no src.
  defp image_replacement(alt, nil), do: [alt]
  # Hyperlink with alt text when both are present.
  defp image_replacement(alt, src), do: [{"a", [{"href", src}], [alt]}]

  defp attr_value(attrs, name) do
    Enum.find_value(attrs, fn {k, v} -> if k == name, do: v end)
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

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
          excerpt_length: pos_integer() | nil,
          sanitize_html: boolean(),
          dropped_tags: [String.t()],
          dropped_attrs: [String.t()]
        }

  @doc """
  Merges a per-feed filter map onto a default filter map.

  `allow_categories` and `block_categories` REPLACE the default value when
  the per-feed map sets them to a list. Other keys override field-by-field.
  Per-feed keys set to `nil` leave the default in place.
  """
  @spec merge(t(), map() | nil) :: t()
  def merge(defaults, nil), do: defaults

  def merge(defaults, per_feed) do
    Map.merge(defaults, per_feed, fn
      _k, v1, nil -> v1
      _k, _v1, v2 -> v2
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

  defp transform(post, filters) do
    post
    |> apply_sanitization(filters)
    |> apply_image_stripping(filters)
    |> apply_excerpt(filters)
  end

  defp apply_sanitization(post, %{sanitize_html: false}), do: post

  defp apply_sanitization(post, %{dropped_tags: dropped_tags, dropped_attrs: dropped_attrs}) do
    post
    |> Map.update!(:body, &scrub_html(&1, dropped_tags, dropped_attrs))
    |> Map.update!(:summary, &scrub_html(&1, dropped_tags, dropped_attrs))
  end

  defp apply_sanitization(post, _filters), do: post

  defp scrub_html(nil, _dropped_tags, _dropped_attrs), do: nil
  defp scrub_html("", _dropped_tags, _dropped_attrs), do: ""

  defp scrub_html(html, dropped_tags, dropped_attrs) when is_binary(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.to_tree()
    |> Enum.flat_map(&scrub_node(&1, dropped_tags, dropped_attrs))
    |> LazyHTML.from_tree()
    |> LazyHTML.to_html()
  end

  defp scrub_node({tag, attrs, children}, dropped_tags, dropped_attrs) when is_binary(tag) do
    if tag in dropped_tags do
      []
    else
      clean_attrs = Enum.reject(attrs, fn {name, _} -> name in dropped_attrs end)
      clean_children = Enum.flat_map(children, &scrub_node(&1, dropped_tags, dropped_attrs))
      [{tag, clean_attrs, clean_children}]
    end
  end

  defp scrub_node({:comment, _} = node, _dropped_tags, _dropped_attrs), do: [node]
  defp scrub_node(text, _dropped_tags, _dropped_attrs) when is_binary(text), do: [text]

  defp apply_image_stripping(post, %{strip_images: true}) do
    post
    |> Map.update!(:body, &maybe_strip_images/1)
    |> Map.update!(:summary, &maybe_strip_images/1)
  end

  defp apply_image_stripping(post, _filters), do: post

  defp apply_excerpt(post, %{excerpt_length: n}) when is_integer(n) and n > 0 do
    %{post | summary: compute_excerpt(post.summary, post.body, n)}
  end

  defp apply_excerpt(post, _filters), do: post

  # If existing summary is already short enough, keep it as-is (preserves the
  # original HTML markup from the feed). Otherwise generate a truncated summary
  # from the body and HTML-escape it: the source HTML's text content may contain
  # decoded `<` / `&` characters (e.g. from a `<pre>` code sample) that would
  # otherwise break the consumer's layout when rendered raw.
  #
  # When no extractable text is available (e.g. body is only images), return
  # `nil` so consumers fall back to the original body via `summary || body`.
  # `""` would mask the body in `||` because empty strings are truthy in Elixir.
  defp compute_excerpt(summary, _body, n) when is_binary(summary) and byte_size(summary) <= n,
    do: summary

  defp compute_excerpt(summary, body, n) do
    text = html_to_text(summary || body || "")

    cond do
      summary && String.length(text) <= n -> summary
      text == "" -> nil
      true -> text |> truncate(n) |> LazyHTML.html_escape()
    end
  end

  defp html_to_text(""), do: ""

  defp html_to_text(html) do
    html
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.trim()
    |> normalize_whitespace()
  end

  defp normalize_whitespace(text), do: String.replace(text, ~r/\s+/, " ")

  # Truncate `text` to at most `n` characters total (including the "…").
  # Cut at the last whitespace before the limit when possible.
  defp truncate(_text, n) when n <= 1, do: "…"

  defp truncate(text, n) do
    if String.length(text) <= n do
      text
    else
      # Reserve one character for the "…".
      budget = n - 1
      head = String.slice(text, 0, budget)

      truncated =
        case Regex.run(~r/\s+\S*\z/, head, return: :index) do
          [{idx, _len}] -> binary_part(head, 0, idx)
          _ -> head
        end
        |> String.trim_trailing()

      truncated <> "…"
    end
  end

  defp maybe_strip_images(nil), do: nil
  defp maybe_strip_images(""), do: ""

  defp maybe_strip_images(html) when is_binary(html) do
    if String.contains?(html, "<img") do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.to_tree()
      |> strip_images_tree()
      |> LazyHTML.from_tree()
      |> LazyHTML.to_html()
    else
      html
    end
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

  # alt="" is HTML5 for "decorative image" — drop it the same as missing alt.
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

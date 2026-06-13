defmodule Exoplanet.Filters do
  @moduledoc """
  Per-feed content filters: HTML sanitization, category allow/block lists,
  image stripping, and summary truncation.

  The sanitizer (`sanitize_html: true`, the default) removes the tags listed
  in `drop_tags`, the attributes listed in `drop_attrs`, every `on*` event
  handler attribute, and any URL-bearing attribute (`href`, `src`, `srcset`,
  `action`, `formaction`, `poster`, `xlink:href`) whose URL
  scheme is not `http`, `https`, or `mailto` (relative URLs are kept).
  It is a defense-in-depth measure for feed content, not a guarantee — if
  you render feed HTML in a security-sensitive context, consider pairing it
  with a dedicated sanitizer such as `html_sanitize_ex`.

  To delegate sanitization entirely, configure an `Exoplanet.Sanitizer`
  adapter:

      config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer

  When set (and `sanitize_html` is `true`), the adapter replaces the built-in
  sanitize step. `strip_images` and `excerpt_length` still apply, after the
  adapter. See `Exoplanet.Sanitizer`.

  ## Category filters

  `allow_categories` accepts a list of strings or `:all` (no allowlist
  constraint). `block_categories` accepts a list of strings or `:none` (no
  blocklist constraint). The empty list `[]` is equivalent to `:all` /
  `:none` respectively and remains supported. Atoms are normalized to `[]`
  internally; see `normalize_categories/1`. The inverses
  (`allow_categories: :none`, `block_categories: :all`) raise
  `ArgumentError` — drop the feed entirely if you want zero posts.
  """

  @type t :: %{
          allow_categories: [String.t()] | :all,
          block_categories: [String.t()] | :none,
          strip_images: boolean(),
          excerpt_length: pos_integer() | nil,
          sanitize_html: boolean(),
          drop_tags: [String.t()],
          drop_attrs: [String.t()]
        }

  # URL-bearing attributes subject to the scheme allowlist when sanitizing.
  @url_attrs ~w(href src srcset action formaction poster xlink:href)
  @allowed_schemes ~w(http https mailto)

  @defaults %{
    allow_categories: [],
    block_categories: [],
    strip_images: false,
    excerpt_length: nil,
    sanitize_html: true,
    drop_tags: ~w(iframe script object embed style base),
    drop_attrs: ~w(style)
  }

  @doc """
  Built-in default filter map. Used by `Exoplanet.Config` as the baseline
  for `default_filters` and as the starting point that user-supplied
  `default_filters` are merged onto.
  """
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc """
  Normalizes the category-filter atoms in a filter map.

  Replaces `allow_categories: :all` with `[]` and `block_categories: :none`
  with `[]`. Lists pass through unchanged. Keys that are missing stay
  missing (no defaults are inserted). Raises `ArgumentError` for any
  other atom value, including `allow_categories: :none` and
  `block_categories: :all` (both nonsensical — drop the feed instead).

  Called automatically by `merge/2` and `Exoplanet.Config.from_file/1`,
  so consumers rarely need to invoke it directly.
  """
  @spec normalize_categories(map()) :: map()
  def normalize_categories(filters) when is_map(filters) do
    filters
    |> normalize_key(:allow_categories, :all, :none)
    |> normalize_key(:block_categories, :none, :all)
  end

  defp normalize_key(filters, key, ok_atom, bad_atom) do
    case Map.fetch(filters, key) do
      :error ->
        filters

      {:ok, list} when is_list(list) ->
        Map.update!(filters, key, fn l -> Enum.map(l, &String.downcase/1) end)

      {:ok, ^ok_atom} ->
        Map.put(filters, key, [])

      {:ok, ^bad_atom} ->
        raise ArgumentError,
              "#{inspect(key)} does not accept #{inspect(bad_atom)} " <>
                "(valid forms are a list of strings or #{inspect(ok_atom)})"

      {:ok, other} ->
        raise ArgumentError,
              "#{inspect(key)} must be a list of strings or #{inspect(ok_atom)}, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc """
  Merges a per-feed filter map onto a default filter map.

  `allow_categories` and `block_categories` REPLACE the default value when
  the per-feed map sets them to a list. Other keys override field-by-field.
  Per-feed keys set to `nil` leave the default in place.

  Defaults are normalized first, then the merged result is normalized,
  so callers may use `allow_categories: :all` or `block_categories: :none`
  on either side. Invalid atoms (`allow_categories: :none`,
  `block_categories: :all`, or any unrecognized atom) raise `ArgumentError`.
  """
  @spec merge(t(), map() | nil) :: t()
  def merge(defaults, nil), do: normalize_categories(defaults)

  def merge(defaults, per_feed) do
    defaults
    |> normalize_categories()
    |> Map.merge(per_feed, fn
      _k, v1, nil -> v1
      _k, _v1, v2 -> v2
    end)
    |> normalize_categories()
  end

  @doc """
  Applies the merged filter map to a list of `Exoplanet.Post` structs.

  Returns the filtered list. Posts dropped by category filters are removed
  entirely. The `sanitize_html` and `strip_images` filters modify each post's
  `:body` and `:summary`. The `excerpt_length` filter modifies only `:summary`.
  Sanitization runs first, then image stripping, then excerpt generation.
  When both built-in HTML filters are enabled they share a single tree walk;
  with a `sanitizer_adapter` configured, sanitization and image stripping run
  as separate passes.
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
    |> apply_html_filters(filters)
    |> apply_excerpt(filters)
  end

  # Optional sanitizer adapter (an `Exoplanet.Sanitizer` implementation). Read
  # per call, mirroring how `Exoplanet.Fetcher` reads `:cache_adapter`.
  defp sanitizer_adapter, do: Application.get_env(:exoplanet, :sanitizer_adapter)

  # Applies sanitization and image stripping. Returns the post unchanged when
  # neither filter is enabled (no parse/serialize cost). The built-in case is a
  # single fused tree walk; the adapter case delegates the sanitize step and
  # runs image stripping as a separate pass.
  #
  # When a `:sanitizer_adapter` is configured and `sanitize_html` is true, the
  # adapter replaces the built-in sanitize walk; `strip_images` then runs after,
  # via the existing strip-only walk.
  defp apply_html_filters(post, filters) do
    sanitize? = Map.get(filters, :sanitize_html, true)
    strip_images? = Map.get(filters, :strip_images, false)
    adapter = sanitizer_adapter()

    cond do
      sanitize? and adapter ->
        post
        |> run_adapter(adapter)
        |> strip_images_only(strip_images?)

      sanitize? ->
        opts = %{
          sanitize?: true,
          drop_tags: MapSet.new(filters.drop_tags),
          # Downcased so user-supplied names like "Style" match the
          # (already-lowercased) attribute names compared in drop_attr?/2.
          drop_attrs: MapSet.new(filters.drop_attrs, &String.downcase/1),
          strip_images?: strip_images?
        }

        transform_html_fields(post, &walk_node(&1, opts), fn _ -> true end)

      strip_images? ->
        # Short-circuit when html has no <img>: parse/serialize would otherwise
        # rewrite e.g. `&` → `&amp;` and `<br>` → `<br/>`, breaking byte equality.
        transform_html_fields(post, &walk_node(&1, strip_only_opts()), &has_img?/1)

      true ->
        post
    end
  end

  # Delegate sanitization of :body and :summary to the configured adapter.
  # The adapter is not invoked on nil/empty fields.
  defp run_adapter(post, adapter) do
    post
    |> Map.update!(:body, &adapter_sanitize(adapter, &1))
    |> Map.update!(:summary, &adapter_sanitize(adapter, &1))
  end

  defp adapter_sanitize(_adapter, nil), do: nil
  defp adapter_sanitize(_adapter, ""), do: ""
  defp adapter_sanitize(adapter, html) when is_binary(html), do: adapter.sanitize(html)

  # Image-stripping pass applied after an adapter has sanitized. Runs the
  # existing strip-only walk. The generated image-replacement <a href> is still
  # scheme-restricted (see image_src/2) since it is exoplanet's own construct.
  # No-op when strip_images is off.
  defp strip_images_only(post, false), do: post

  defp strip_images_only(post, true) do
    transform_html_fields(post, &walk_node(&1, strip_only_opts()), &has_img?/1)
  end

  # Walk options for an image-stripping-only pass (no tag/attr/scheme dropping).
  defp strip_only_opts do
    %{sanitize?: false, drop_tags: MapSet.new(), drop_attrs: MapSet.new(), strip_images?: true}
  end

  defp transform_html_fields(post, walker, needs?) do
    post
    |> Map.update!(:body, &transform_html(&1, walker, needs?))
    |> Map.update!(:summary, &transform_html(&1, walker, needs?))
  end

  # Generic HTML transform: parse → walk top-level nodes → serialize. Walker
  # may drop or expand each node by returning a (possibly empty) list. Skips
  # the parse/serialize round-trip when `needs?` returns false for the input.
  defp transform_html(nil, _walker, _needs?), do: nil
  defp transform_html("", _walker, _needs?), do: ""

  defp transform_html(html, walker, needs?) when is_binary(html) do
    if needs?.(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.to_tree()
      |> Enum.flat_map(walker)
      |> LazyHTML.from_tree()
      |> LazyHTML.to_html()
    else
      html
    end
  end

  defp has_img?(html), do: html =~ ~r/<img\b/i

  defp walk_node({tag, attrs, children}, opts) when is_binary(tag) do
    cond do
      tag in opts.drop_tags ->
        []

      opts.strip_images? and tag == "img" ->
        image_replacement(attr_value(attrs, "alt"), image_src(attrs, opts))

      true ->
        clean_attrs = Enum.reject(attrs, &drop_attr?(&1, opts))
        clean_children = Enum.flat_map(children, &walk_node(&1, opts))
        [{tag, clean_attrs, clean_children}]
    end
  end

  defp walk_node(node, _opts), do: [node]

  # Attributes named in `drop_attrs` are always removed. When sanitizing,
  # also remove `on*` event handlers and URL attributes with a disallowed
  # scheme — those are the standard markup-injection vectors that survive
  # tag-level filtering.
  defp drop_attr?({name, value}, opts) do
    name = String.downcase(name)

    name in opts.drop_attrs or
      (opts.sanitize? and
         (String.starts_with?(name, "on") or
            (name in @url_attrs and not safe_url_value?(name, value))))
  end

  # The src used for the generated image-replacement link must always pass the
  # scheme allowlist — the <a href> is exoplanet's own construct, so this is an
  # output-safety invariant, not re-sanitization of the source HTML. Applies
  # even when the surrounding pass has `sanitize?: false` (e.g. strip-only, or
  # after a sanitizer adapter), so stripping an image can never smuggle a
  # javascript:/data: URL into a clickable link.
  defp image_src(attrs, _opts) do
    case attr_value(attrs, "src") do
      nil -> nil
      src -> if safe_url?(src), do: src, else: nil
    end
  end

  # srcset is a comma-separated list of "url [descriptor]" candidates; every
  # candidate URL must be safe for the attribute to survive.
  defp safe_url_value?("srcset", value) do
    value
    |> String.split(",")
    |> Enum.all?(fn candidate ->
      candidate |> String.trim() |> String.split(~r/\s+/) |> hd() |> safe_url?()
    end)
  end

  defp safe_url_value?(_name, value), do: safe_url?(value)

  # A URL is safe when it is relative (no scheme) or its scheme is in the
  # allowlist. ASCII control characters and whitespace are stripped before
  # the scheme check because HTML parsers tolerate them inside the scheme
  # (e.g. "java\nscript:"), which would otherwise defeat a naive match.
  defp safe_url?(url) when is_binary(url) do
    compact = String.replace(url, ~r/[\x00-\x20]/, "")

    case Regex.run(~r/^([a-zA-Z][a-zA-Z0-9+.-]*):/, compact) do
      [_, scheme] -> String.downcase(scheme) in @allowed_schemes
      nil -> true
    end
  end

  defp safe_url?(_), do: false

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

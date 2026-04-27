defmodule Exoplanet.Parser do
  @moduledoc false
  require Logger

  def parse({url, %{name: name}}, config) do
    case fetch_body(url, config) do
      nil ->
        []

      body ->
        raw_items =
          if rss_body?(body),
            do: parse_rss(url, body, name),
            else: parse_atom(url, body, name)

        Enum.map(raw_items, fn {attrs, content} -> Exoplanet.Post.build(attrs, content) end)
    end
  end

  # Fetches the feed body, using the configured cache adapter for conditional
  # GET when available. Returns the body string, or nil on an uncached error.
  defp fetch_body(url, config) do
    {conditional_headers, cached_entry} = build_conditional_headers(url, config)

    base_opts = Application.get_env(:exoplanet, :planet_req_options, [])
    opts = merge_headers(base_opts, conditional_headers)

    case Req.get(url, opts) do
      {:ok, %{status: 304}} ->
        Logger.debug("Feed #{url}: 304 Not Modified, using cached body")
        maybe_notify_success(url, 304)
        cached_entry && cached_entry.body

      {:ok, %{status: 200, body: body} = resp} ->
        # maybe_update_cache stores etag/body; maybe_notify_success resets error state.
        # Both write to the feeds table on cacheable responses — intentional trade-off.
        maybe_update_cache(url, resp, body)
        maybe_notify_success(url, 200)
        body

      {:ok, %{status: status}} ->
        Logger.error("Feed #{url}: unexpected HTTP status #{status}")
        maybe_notify_error(url, status, "HTTP #{status}")
        cached_entry && cached_entry.body

      {:error, reason} ->
        Logger.error(
          "something went wrong while retrieving URL: #{url}, reason: #{inspect(reason)}"
        )

        maybe_notify_error(url, nil, inspect(reason))

        # Fall back to cached body (if any) so a transient error doesn't blank
        # out content we already have.
        cached_entry && cached_entry.body
    end
  end

  defp cache_adapter, do: Application.get_env(:exoplanet, :cache_adapter)

  defp maybe_notify_success(url, status) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        if function_exported?(adapter, :on_success, 2) do
          adapter.on_success(url, status)
        end

        :ok
    end
  end

  defp maybe_notify_error(url, status, reason) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        if function_exported?(adapter, :on_error, 3) do
          adapter.on_error(url, status, reason)
        end

        :ok
    end
  end

  defp build_conditional_headers(url, _config) do
    case cache_adapter() do
      nil ->
        {[], nil}

      adapter ->
        case adapter.get(url) do
          %{etag: etag, last_modified: last_modified} = entry ->
            headers =
              []
              |> prepend_if(etag, {"if-none-match", etag})
              |> prepend_if(last_modified, {"if-modified-since", last_modified})

            {headers, entry}

          nil ->
            {[], nil}
        end
    end
  end

  defp maybe_update_cache(url, resp, body) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        etag = get_response_header(resp, "etag")
        last_modified = get_response_header(resp, "last-modified")

        if etag || last_modified do
          adapter.put(url, %{etag: etag, last_modified: last_modified, body: body})
        end

        :ok
    end
  end

  # Req 0.5 stores response headers as %{String.t() => [String.t()]}
  defp get_response_header(%{headers: headers}, name) do
    case Map.get(headers, name, []) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp merge_headers(opts, []), do: opts

  defp merge_headers(opts, extra_headers) do
    Keyword.update(opts, :headers, extra_headers, fn existing ->
      existing ++ extra_headers
    end)
  end

  defp prepend_if(list, condition, item) do
    if condition, do: [item | list], else: list
  end

  # RSS 2.0 uses <rss ...>, RSS 1.0 uses <rdf:RDF ...>. Both need parse_rss.
  # Atom uses <feed ...>. Anything else falls through to parse_atom and may fail.
  defp rss_body?(body) do
    String.contains?(body, "<rss") or String.contains?(body, "<rdf:RDF")
  end

  @doc false
  def parse_rss(url, body, name) do
    case FastRSS.parse_rss(body) do
      {:ok, %{"items" => items}} ->
        Enum.map(items, fn item ->
          title = item["title"]
          content = item["description"]
          authors = normalize_authors([item["author"]], name)

          categories =
            (item["categories"] || []) |> Enum.map(& &1["name"]) |> normalize_categories()

          id = item["link"] || get_in(item, ["guid", "value"])
          published = item["pub_date"] && Exoplanet.DateTimeParser.parse!(item["pub_date"])

          attrs = %{
            feed_url: url,
            authors: authors,
            title: title,
            categories: categories,
            id: id,
            published: published
          }

          {attrs, content}
        end)

      {:error, reason} ->
        Logger.error("something went wrong while parsing feed #{url}, reason: #{inspect(reason)}")
        []
    end
  end

  @doc false
  def parse_atom(url, body, name) do
    case FastRSS.parse_atom(body) do
      {:ok, %{"entries" => entries}} ->
        Enum.map(entries, fn entry ->
          title = get_in(entry, ["title", "value"])
          content = get_in(entry, ["content", "value"])
          authors = normalize_authors(get_in(entry, ["authors", Access.all(), "name"]), name)

          categories =
            get_in(entry, ["categories", Access.all(), "term"]) |> normalize_categories()

          id = Map.get(entry, "id")
          published = entry["published"] && NaiveDateTime.from_iso8601!(entry["published"])
          updated = entry["updated"] && NaiveDateTime.from_iso8601!(entry["updated"])
          summary = blank_to_nil(get_in(entry, ["summary", "value"]))

          attrs = %{
            feed_url: url,
            authors: authors,
            title: title,
            categories: categories,
            id: id,
            published: published || updated,
            updated: updated,
            summary: summary
          }

          {attrs, content}
        end)

      {:error, reason} ->
        Logger.error("something went wrong while parsing feed #{url}, reason: #{inspect(reason)}")
        []
    end
  end

  defp normalize_categories([]), do: nil
  defp normalize_categories(cats), do: cats

  # Drop blank/whitespace-only author names; fall back to the source's
  # configured `name` if nothing meaningful is left.
  defp normalize_authors(nil, fallback), do: [fallback]

  defp normalize_authors(authors, fallback) when is_list(authors) do
    case Enum.reject(authors, &blank?/1) do
      [] -> [fallback]
      kept -> kept
    end
  end

  defp blank_to_nil(value) do
    if blank?(value), do: nil, else: value
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end

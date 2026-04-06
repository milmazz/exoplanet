defmodule Exoplanet.Parser do
  @moduledoc false
  require Logger

  def parse(%Exoplanet.Config{sources: sources} = config) do
    sources
    |> Task.async_stream(__MODULE__, :parse, [config],
      ordered: false,
      timeout: to_timeout(second: config.feed_timeout)
    )
    |> Stream.flat_map(fn result ->
      case result do
        {:ok, posts} -> posts
        _ -> []
      end
    end)
  end

  def parse({url, %{name: name} = _attrs}, config) do
    # TODO: Apply filters (e.g., remove images from posts)
    case fetch_body(url, config) do
      nil ->
        []

      body ->
        items =
          if String.contains?(body, "<rss version="),
            do: parse_rss(url, body, name),
            else: parse_atom(url, body, name)

        Enum.take(items, config.new_feed_items)
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
        cached_entry.body

      {:ok, %{status: 200, body: body} = resp} ->
        maybe_update_cache(url, resp, body)
        body

      # TODO: Handle other status codes like 404, 301, etc.
      {:error, reason} ->
        Logger.error(
          "something went wrong while retrieving URL: #{url}, reason: #{inspect(reason)}"
        )

        # Fall back to cached body (if any) so a transient error doesn't blank
        # out content we already have.
        cached_entry && cached_entry.body
    end
  end

  defp cache_adapter, do: Application.get_env(:exoplanet, :cache_adapter)

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

  @doc false
  def parse_rss(url, body, name) do
    case FastRSS.parse_rss(body) do
      {:ok, %{"items" => items}} ->
        parsed_items =
          Enum.map(items, fn item ->
            title = item["title"]
            content = item["description"]
            authors = List.wrap(item["author"] || name)
            categories = item["categories"]
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

        parsed_items

      {:error, reason} ->
        Logger.error("something went wrong while parsing feed #{url}, reason: #{inspect(reason)}")
        []
    end
  end

  @doc false
  def parse_atom(url, body, name) do
    case FastRSS.parse_atom(body) do
      {:ok, %{"entries" => entries}} ->
        parsed_entries =
          Enum.map(entries, fn entry ->
            title = get_in(entry, ["title", "value"])
            content = get_in(entry, ["content", "value"])
            authors = get_in(entry, ["authors", Access.all(), "name"])
            categories = get_in(entry, ["categories", Access.all(), "term"])
            id = Map.get(entry, "id")
            published = entry["published"] && NaiveDateTime.from_iso8601!(entry["published"])
            updated = entry["updated"] && NaiveDateTime.from_iso8601!(entry["updated"])
            summary = get_in(entry, ["summary", "value"])

            authors = if authors == [], do: [name], else: authors

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

        parsed_entries

      {:error, reason} ->
        Logger.error("something went wrong while parsing feed #{url}, reason: #{inspect(reason)}")

        []
    end
  end
end

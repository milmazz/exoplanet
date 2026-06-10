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
    {conditional_headers, cached_entry} = build_conditional_headers(url)

    opts =
      [receive_timeout: to_timeout(second: config.feed_timeout)]
      |> Keyword.merge(req_options())
      |> merge_headers(conditional_headers)

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

  # Extra options forwarded to `Req.get/2` (user-agent, proxy, retry policy,
  # test plugs, ...). `:planet_req_options` is the deprecated pre-0.6 name,
  # kept as a fallback for existing consumers.
  defp req_options do
    Application.get_env(:exoplanet, :req_options) ||
      Application.get_env(:exoplanet, :planet_req_options, [])
  end

  defp cache_adapter, do: Application.get_env(:exoplanet, :cache_adapter)

  defp maybe_notify_success(url, status), do: maybe_call_adapter(:on_success, [url, status])

  defp maybe_notify_error(url, status, reason),
    do: maybe_call_adapter(:on_error, [url, status, reason])

  defp maybe_call_adapter(callback, args) do
    case cache_adapter() do
      nil ->
        :ok

      adapter ->
        # `function_exported?/3` returns false for modules that haven't been
        # loaded yet (e.g. in dev/interactive mode), so ensure the adapter is
        # loaded before probing for the optional callback.
        if Code.ensure_loaded?(adapter) and function_exported?(adapter, callback, length(args)) do
          apply(adapter, callback, args)
        end

        :ok
    end
  end

  defp build_conditional_headers(url) do
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

  defp parse_rss(url, body, name) do
    case FastRSS.parse_rss(body) do
      {:ok, %{"items" => items}} ->
        Enum.flat_map(items, fn item ->
          case rss_published(item, url) do
            :skip ->
              []

            {:ok, nil} ->
              # No usable date (neither <pubDate> nor <dc:date>) — drop the entry;
              # without a date it can't participate in the chronological merge.
              []

            {:ok, published} ->
              title = item["title"]
              # Prefer <content:encoded> (Content RSS module) over <description> —
              # feeds like Medium put the full HTML article in content:encoded and
              # leave description short or empty.
              content = blank_to_nil(item["content"]) || item["description"]
              authors = normalize_authors(rss_authors(item), name)

              categories =
                (item["categories"] || []) |> Enum.map(& &1["name"]) |> clean_categories()

              id = item["link"] || get_in(item, ["guid", "value"])

              attrs = %{
                feed_url: url,
                authors: authors,
                title: title,
                categories: categories,
                id: id,
                published: published
              }

              [{attrs, content}]
          end
        end)

      {:error, reason} ->
        log_parse_error(url, reason)
    end
  end

  defp parse_atom(url, body, name) do
    case FastRSS.parse_atom(body) do
      {:ok, %{"entries" => entries}} ->
        Enum.flat_map(entries, fn entry ->
          with {:ok, published} <- parse_naive_datetime(entry["published"], url, :iso8601),
               {:ok, updated} <- parse_naive_datetime(entry["updated"], url, :iso8601),
               # FastRSS injects 1970-01-01 epoch when <updated> is absent;
               # treat that sentinel as missing so we skip dateless entries.
               updated = denull_atom_updated(updated),
               timestamp when not is_nil(timestamp) <- published || updated do
            title = get_in(entry, ["title", "value"])
            content = get_in(entry, ["content", "value"])
            authors = normalize_authors(get_in(entry, ["authors", Access.all(), "name"]), name)

            categories =
              get_in(entry, ["categories", Access.all(), "term"]) |> clean_categories()

            # Atom <id> is an IRI per RFC 4287 §4.2.6 — generators like
            # Bridgetown legitimately emit non-URL URNs (e.g. `repo://...`).
            # Such an IRI is unusable as a clickable post URL, so prefer the
            # canonical web link from `<link rel="alternate">` (the spec
            # default rel) and fall back to <id> only when no usable
            # alternate link is present.
            id = atom_post_id(entry)
            summary = blank_to_nil(get_in(entry, ["summary", "value"]))

            attrs = %{
              feed_url: url,
              authors: authors,
              title: title,
              categories: categories,
              id: id,
              published: timestamp,
              updated: updated,
              summary: summary
            }

            [{attrs, content}]
          else
            # `:skip` from parse_naive_datetime, or `nil` from the timestamp
            # check (entry has neither <published> nor <updated> — drop it).
            _ -> []
          end
        end)

      {:error, reason} ->
        log_parse_error(url, reason)
    end
  end

  defp log_parse_error(url, reason) do
    Logger.error("Feed #{url}: parse failed — #{inspect(reason)}")
    []
  end

  # Pick the best available RSS publication date: prefer <pubDate> (RFC 822),
  # then fall back to the first Dublin Core <dc:date> (ISO 8601). FastRSS exposes
  # the latter under "dublin_core_ext" — RSS 1.0 feeds rely on it because the
  # 1.0 spec doesn't define <pubDate>.
  defp rss_published(item, url) do
    case item["pub_date"] do
      nil ->
        case get_in(item, ["dublin_core_ext", "dates"]) do
          [date | _] -> parse_naive_datetime(date, url, :iso8601)
          _ -> {:ok, nil}
        end

      value ->
        parse_naive_datetime(value, url, :rfc822)
    end
  end

  # FastRSS substitutes the Unix epoch when an Atom <updated> element is absent;
  # we collapse that sentinel to `nil` so dateless entries can be detected.
  defp denull_atom_updated(~N[1970-01-01 00:00:00]), do: nil
  defp denull_atom_updated(other), do: other

  # Pick the best post id for an Atom entry: prefer the first
  # `<link rel="alternate">` href (the canonical web URL), then any link
  # whose `rel` is missing — RFC 4287 §4.2.7.2 says an absent rel defaults
  # to "alternate" — and finally fall back to <id>.
  defp atom_post_id(entry) do
    links = Map.get(entry, "links", [])

    alternate =
      Enum.find_value(links, fn
        %{"rel" => "alternate", "href" => href} when is_binary(href) ->
          blank_to_nil(href)

        %{"rel" => rel, "href" => href} when rel in [nil, ""] and is_binary(href) ->
          blank_to_nil(href)

        _ ->
          nil
      end)

    alternate || Map.get(entry, "id")
  end

  # Parse a feed-entry timestamp. Returns:
  #   * `{:ok, nil}` — value missing (caller treats absent date as OK)
  #   * `{:ok, NaiveDateTime.t()}` — parsed successfully
  #   * `:skip` — value present but unparseable (caller drops the entry)
  # A warning is logged before returning `:skip` so operators can see which feed
  # produced the bad value.
  defp parse_naive_datetime(nil, _url, _kind), do: {:ok, nil}

  defp parse_naive_datetime(value, url, :rfc822) do
    case Exoplanet.DateTimeParser.parse(value) do
      {:ok, dt} ->
        {:ok, dt}

      _ ->
        Logger.warning("Feed #{url}: unparseable RFC822 date #{inspect(value)} — skipping post")
        :skip
    end
  end

  defp parse_naive_datetime(value, url, :iso8601) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, dt} ->
        {:ok, dt}

      {:error, _} ->
        Logger.warning("Feed #{url}: unparseable ISO8601 date #{inspect(value)} — skipping post")
        :skip
    end
  end

  # Trim whitespace and trailing punctuation (`,`, `;`) from each category
  # value before downstream filter matching. Some feeds emit category text
  # like "otp," or "release," (presumably a templating bug on the producer
  # side) which would otherwise miss case-insensitive equality with "otp"
  # in the allow/block lists. Empty results after trimming are dropped, and
  # an entirely empty list is normalised to `nil`.
  #
  # Named `clean_categories` (not `normalize_categories`) to avoid colliding
  # with `Exoplanet.Filters.normalize_categories/1`, which has unrelated
  # semantics (filter-atom normalization).
  defp clean_categories(nil), do: nil

  defp clean_categories(cats) when is_list(cats) do
    Enum.flat_map(cats, fn cat ->
      case clean_category(cat) do
        nil -> []
        cleaned -> [cleaned]
      end
    end)
  end

  defp clean_category(nil), do: nil

  defp clean_category(value) when is_binary(value) do
    trimmed =
      value
      |> String.downcase()
      |> String.trim()
      |> String.trim_trailing(",")
      |> String.trim_trailing(";")
      |> String.trim()

    if trimmed == "", do: nil, else: trimmed
  end

  defp clean_category(_), do: nil

  # Drop blank/whitespace-only author names; fall back to the source's
  # configured `name` if nothing meaningful is left.
  defp normalize_authors(nil, fallback), do: [fallback]

  defp normalize_authors(authors, fallback) when is_list(authors) do
    case Enum.reject(authors, &blank?/1) do
      [] -> [fallback]
      kept -> kept
    end
  end

  # Prefer Dublin Core <dc:creator> over RSS 2.0 <author>. The RSS spec defines
  # <author> as an email address; in practice most blogs leave it empty and put
  # the human name in <dc:creator>. FastRSS exposes the latter as a list under
  # dublin_core_ext.creators.
  defp rss_authors(item) do
    case get_in(item, ["dublin_core_ext", "creators"]) do
      [_ | _] = creators -> creators
      _ -> [item["author"]]
    end
  end

  defp blank_to_nil(value) do
    if blank?(value), do: nil, else: value
  end

  defp blank?(nil), do: true
  defp blank?(s) when is_binary(s), do: String.trim(s) == ""
  defp blank?(_), do: false
end

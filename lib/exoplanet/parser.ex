defmodule Exoplanet.Parser do
  @moduledoc false
  require Logger

  # Pure feed parser: turns a fetched feed body into built `%Exoplanet.Post{}`
  # structs. HTTP and cache interaction live in `Exoplanet.Fetcher`; the
  # orchestrator (`Exoplanet.build_source/3`) fetches first and only calls this
  # with a real binary body.
  def parse(body, url, name) when is_binary(body) do
    raw_items =
      if rss_body?(body),
        do: parse_rss(url, body, name),
        else: parse_atom(url, body, name)

    Enum.map(raw_items, fn {attrs, content} -> Exoplanet.Post.build(attrs, content) end)
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

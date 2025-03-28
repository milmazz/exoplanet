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
    case Req.get(url, Application.get_env(:exoplanet, :planet_req_options, [])) do
      {:ok, %{status: 200, body: body}} ->
        items =
          if String.contains?(body, "<rss version="),
            do: parse_rss(url, body, name),
            else: parse_atom(url, body, name)

        Enum.take(items, config.new_feed_items)

      # TODO: Handle other status codes like 404, 301, etc.
      {:error, reason} ->
        Logger.error(
          "something went wrong while retrieving URL: #{url}, reason: #{inspect(reason)}"
        )

        []
    end
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

            authors = if authors == [], do: [name], else: authors

            attrs = %{
              authors: authors,
              title: title,
              categories: categories,
              id: id,
              published: published,
              updated: updated
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

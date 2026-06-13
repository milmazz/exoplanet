defmodule Exoplanet.Fetcher do
  @moduledoc false
  require Logger

  # Fetches the feed body, using the configured cache adapter for conditional
  # GET when available. Returns the body string, or nil on an uncached error.
  def fetch(url, config) do
    {conditional_headers, cached_entry} = build_conditional_headers(url)

    # Retries are off by default: with the feed_timeout task backstop in
    # `Exoplanet.build/1` a retried request could never finish anyway, and a
    # prompt error return is what lets us fall back to the cached body.
    # Consumers can re-enable retries via the :req_options app env key.
    opts =
      [receive_timeout: to_timeout(second: config.feed_timeout), retry: false]
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
    case Application.get_env(:exoplanet, :req_options) do
      nil ->
        case Application.get_env(:exoplanet, :planet_req_options) do
          nil ->
            []

          legacy ->
            warn_legacy_req_options()
            legacy
        end

      opts ->
        opts
    end
  end

  # Warn once per VM, not once per feed fetch — a planet rebuild touches
  # every source and would otherwise repeat this for each of them.
  defp warn_legacy_req_options do
    unless :persistent_term.get({__MODULE__, :legacy_req_options_warned}, false) do
      :persistent_term.put({__MODULE__, :legacy_req_options_warned}, true)

      Logger.warning(
        "the :planet_req_options application env key is deprecated; " <>
          "rename it to :req_options (config :exoplanet, req_options: [...])"
      )
    end
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
end

defmodule Exoplanet.Cache do
  @moduledoc """
  Behaviour for feed HTTP conditional-GET cache adapters.

  Implementations are responsible for their own configuration.
  No path or directory is threaded through the interface — each adapter
  reads what it needs from its own application environment.

  Configure the active adapter in the consuming application:

      config :exoplanet, cache_adapter: MyApp.FeedCache

  Set to `nil` (or omit) to disable caching entirely.
  """

  @type url :: String.t()

  @type entry :: %{
          etag: String.t() | nil,
          last_modified: String.t() | nil,
          body: String.t()
        }

  @doc """
  Returns the cached entry for the given URL, or `nil` if absent.
  """
  @callback get(url()) :: entry() | nil

  @doc """
  Stores (or replaces) the cache entry for the given URL. Returns `:ok`.
  """
  @callback put(url(), entry()) :: :ok

  @doc """
  Called when a fetch fails (non-200/304 response or connection error).
  `status` is the HTTP status code, or `nil` for connection-level failures.
  `reason` is a human-readable error string (e.g. `"HTTP 404"`).
  """
  @callback on_error(url(), status :: integer() | nil, reason :: String.t()) :: :ok

  @doc """
  Called when a fetch succeeds (200 or 304). `status` is the HTTP status code.
  """
  @callback on_success(url(), status :: integer()) :: :ok

  @optional_callbacks on_error: 3, on_success: 2
end

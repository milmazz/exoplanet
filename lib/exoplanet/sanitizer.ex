defmodule Exoplanet.Sanitizer do
  @moduledoc """
  Behaviour for delegating feed-content HTML sanitization to an external
  library.

  `Exoplanet.Filters` ships a built-in sanitizer (`sanitize_html: true`, the
  default) that is defense-in-depth, not a guarantee. For security-sensitive
  rendering you can delegate to a comprehensive sanitizer by implementing this
  behaviour and configuring it:

      config :exoplanet, sanitizer_adapter: MyApp.FeedSanitizer

  When an adapter is configured **and** `sanitize_html` is `true`, the adapter
  **replaces** the built-in sanitizer — it is the single authority for what
  HTML is allowed. The built-in `drop_tags`/`drop_attrs`/scheme-allowlist walk
  does not run. The `strip_images` and `excerpt_length` filters are content
  shaping (not sanitization) and still run, after the adapter. Image-replacement
  links produced by `strip_images` remain scheme-restricted
  (`http`/`https`/`mailto` or relative), since those links are constructed by
  Exoplanet itself. Setting `sanitize_html: false` disables sanitization
  entirely and the adapter is not called.

  Set `:sanitizer_adapter` to `nil` (or omit it) to use the built-in sanitizer.

  ## Example adapter

  `html_sanitize_ex` is not a dependency of Exoplanet; add it to your own
  application and wrap it:

      defmodule MyApp.FeedSanitizer do
        @behaviour Exoplanet.Sanitizer

        @impl true
        def sanitize(html), do: HtmlSanitizeEx.basic_html(html)
      end

  The callback is invoked once per HTML field (a post's `body` and `summary`)
  with a binary and must return a binary. It is not called for `nil` or empty
  fields.
  """

  @doc """
  Sanitizes one HTML fragment (a post's `body` or `summary`) and returns the
  cleaned HTML.
  """
  @callback sanitize(html :: String.t()) :: String.t()
end

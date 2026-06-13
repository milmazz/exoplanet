defmodule Exoplanet.FiltersSanitizerTest do
  use ExUnit.Case, async: false

  alias Exoplanet.Filters

  # Adapter that returns its input verbatim — proves the built-in walk is
  # BYPASSED (an <iframe>, which the built-in drops, must survive).
  defmodule PassthroughSanitizer do
    @behaviour Exoplanet.Sanitizer
    @impl true
    def sanitize(html), do: html
  end

  defp post(attrs) do
    struct(
      Exoplanet.Post,
      Map.merge(%{body: nil, summary: nil, categories: nil, published: nil}, attrs)
    )
  end

  defp filters(overrides \\ %{}) do
    Map.merge(Exoplanet.Filters.defaults(), overrides)
  end

  setup do
    on_exit(fn -> Application.delete_env(:exoplanet, :sanitizer_adapter) end)
    :ok
  end

  test "a configured adapter replaces the built-in sanitizer" do
    Application.put_env(:exoplanet, :sanitizer_adapter, PassthroughSanitizer)

    html = ~s(<p>hi</p><iframe src="https://e/x"></iframe>)
    [out] = Filters.apply([post(%{body: html})], filters())

    # Built-in would drop <iframe>; the passthrough adapter keeps it, proving
    # the built-in walk did not run.
    assert out.body =~ "<iframe"
  end
end

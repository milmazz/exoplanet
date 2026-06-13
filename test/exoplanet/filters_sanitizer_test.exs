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

  # Removes the literal marker "SECRET" — proves the adapter's effect lands.
  defmodule RedactingSanitizer do
    @behaviour Exoplanet.Sanitizer
    @impl true
    def sanitize(html), do: String.replace(html, "SECRET", "***")
  end

  # Records every input it sees in an Agent named __MODULE__, then returns the
  # html unchanged. Lets tests assert which fields the adapter was called with.
  defmodule RecordingSanitizer do
    @behaviour Exoplanet.Sanitizer

    def child_spec(_), do: %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
    def start_link, do: Agent.start_link(fn -> [] end, name: __MODULE__)
    def calls, do: Agent.get(__MODULE__, &Enum.reverse/1)

    @impl true
    def sanitize(html) do
      Agent.update(__MODULE__, &[html | &1])
      html
    end
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

  test "the adapter's transformation appears in body and summary" do
    Application.put_env(:exoplanet, :sanitizer_adapter, RedactingSanitizer)

    [out] =
      Filters.apply(
        [post(%{body: "<p>SECRET body</p>", summary: "<p>SECRET summary</p>"})],
        filters()
      )

    assert out.body == "<p>*** body</p>"
    assert out.summary == "<p>*** summary</p>"
  end

  test "the adapter is not called when sanitize_html is false" do
    Application.put_env(:exoplanet, :sanitizer_adapter, RecordingSanitizer)
    start_supervised!(RecordingSanitizer)

    html = ~s(<p>hi</p><iframe></iframe>)
    [out] = Filters.apply([post(%{body: html})], filters(%{sanitize_html: false}))

    assert RecordingSanitizer.calls() == []
    # No sanitization at all: body is untouched (iframe survives).
    assert out.body == html
  end

  test "the adapter is called once per non-empty field, skipping nil/empty" do
    Application.put_env(:exoplanet, :sanitizer_adapter, RecordingSanitizer)
    start_supervised!(RecordingSanitizer)

    Filters.apply([post(%{body: "<p>b</p>", summary: ""})], filters())
    # body is sanitized; summary "" is skipped; nil fields are skipped.
    assert RecordingSanitizer.calls() == ["<p>b</p>"]
  end

  test "strip_images runs after the adapter" do
    Application.put_env(:exoplanet, :sanitizer_adapter, PassthroughSanitizer)

    html = ~s(<p>x</p><img src="https://e/x.png" alt="Pic">)
    [out] = Filters.apply([post(%{body: html})], filters(%{strip_images: true}))

    # Adapter kept the <img>; the strip pass then rewrote it to a text link.
    refute out.body =~ "<img"
    assert out.body =~ ~s(<a href="https://e/x.png">Pic</a>)
  end

  test "strip_images does not promote a javascript: img src into a clickable href" do
    Application.put_env(:exoplanet, :sanitizer_adapter, PassthroughSanitizer)

    html = ~s{<p>x</p><img src="javascript:alert(1)" alt="click me">}
    [out] = Filters.apply([post(%{body: html})], filters(%{strip_images: true}))

    # The adapter kept the <img>; exoplanet's strip pass must NOT move the
    # javascript: URL into an <a href>. A disallowed scheme drops the href,
    # leaving just the alt text.
    refute out.body =~ "javascript:"
    refute out.body =~ "<a"
    assert out.body =~ "click me"
  end

  test "with no adapter configured, output matches the built-in sanitizer" do
    # :sanitizer_adapter is unset (setup deletes it on exit; not set here).
    html = ~s|<p>ok</p><script>evil()</script>|
    [out] = Filters.apply([post(%{body: html})], filters())

    refute out.body =~ "<script"
    assert out.body =~ "<p>ok</p>"
  end

  # SVG SMIL animation can set an ancestor <a>'s href to a javascript: URL via
  # the animation element's `to`/`values` attributes — attribute names the
  # URL-scheme allowlist doesn't cover. These elements are in the default
  # drop_tags so the whole element (payload included) is removed.
  test "default sanitizer drops SVG SMIL animation elements carrying javascript:" do
    for {label, html} <- [
          {"animate",
           ~s|<svg><a><animate attributeName="href" values="javascript:alert(1)"/><text>x</text></a></svg>|},
          {"set", ~s|<svg><a><set attributeName="href" to="javascript:alert(1)"/></a></svg>|},
          {"animateTransform",
           ~s|<svg><animateTransform attributeName="href" to="javascript:alert(1)"/></svg>|},
          {"animateMotion",
           ~s|<svg><animateMotion attributeName="href" values="javascript:alert(1)"/></svg>|}
        ] do
      [out] = Filters.apply([post(%{body: html})], filters())

      refute out.body =~ "javascript:", "#{label}: javascript: payload survived sanitization"
      refute out.body =~ "<#{label}", "#{label}: animation element survived sanitization"
    end
  end
end

defmodule Exoplanet.TestHelpers do
  # Shared helpers for the test suite: feed fixtures and `Req.Test` stubs.
  #
  # XML fixtures live in `test/support/fixtures/feeds/<name>.xml` and are loaded
  # on demand. The two stub helpers cover the common cases:
  #
  #   * `stub_feed(:atom)` — every request returns the same fixture
  #   * `stub_feeds(%{"host.example" => :atom, ...})` — dispatches by `conn.host`
  @moduledoc false

  @fixtures_dir Path.expand("fixtures/feeds", __DIR__)

  @doc "Read a feed fixture as a binary."
  def fixture(name) when is_atom(name) do
    File.read!(Path.join(@fixtures_dir, "#{name}.xml"))
  end

  @doc "Stub `Exoplanet.Parser` to return the given fixture for every request."
  def stub_feed(name) when is_atom(name) do
    body = fixture(name)
    Req.Test.stub(Exoplanet.Parser, fn conn -> Req.Test.html(conn, body) end)
  end

  @doc """
  Stub `Exoplanet.Parser` to dispatch by `conn.host` to a fixture name.
  Useful for multi-source tests (e.g. ordering across feeds).
  """
  def stub_feeds(routes) when is_map(routes) do
    bodies = Map.new(routes, fn {host, name} -> {host, fixture(name)} end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, Map.fetch!(bodies, conn.host))
    end)
  end

  @doc "Stub `Exoplanet.Parser` to return a raw XML body (for inline malformed inputs)."
  def stub_body(body) when is_binary(body) do
    Req.Test.stub(Exoplanet.Parser, fn conn -> Req.Test.html(conn, body) end)
  end
end

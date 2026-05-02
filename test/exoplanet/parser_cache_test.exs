defmodule Exoplanet.ParserCacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Exoplanet.TestSupport

  # In-memory cache adapter backed by an Agent. Implements Exoplanet.Cache so
  # it can be wired in via Application.put_env(:exoplanet, :cache_adapter, ...).
  defmodule TestCacheAdapter do
    @behaviour Exoplanet.Cache

    def start(entries \\ %{}) do
      Agent.start(fn -> entries end, name: __MODULE__)
    end

    def stop do
      if Process.whereis(__MODULE__), do: Agent.stop(__MODULE__)
    end

    @impl Exoplanet.Cache
    def get(url), do: Agent.get(__MODULE__, &Map.get(&1, url))

    @impl Exoplanet.Cache
    def put(url, entry) do
      Agent.update(__MODULE__, &Map.put(&1, url, entry))
      :ok
    end
  end

  setup do
    Application.put_env(:exoplanet, :cache_adapter, TestCacheAdapter)
    on_exit(fn -> Application.put_env(:exoplanet, :cache_adapter, nil) end)
    :ok
  end

  test "304 Not Modified uses cached body" do
    url = "https://www.theerlangelist.com/rss"

    {:ok, _} =
      TestCacheAdapter.start(%{
        url => %{etag: "\"abc123\"", last_modified: nil, body: fixture(:rss)}
      })

    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Plug.Conn.send_resp(conn, 304, "")
    end)

    [post] = Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

    assert post.title == "Sequences"
    assert post.feed_url == url
  end

  test "network error falls back to cached body" do
    url = "https://www.theerlangelist.com/rss"

    {:ok, _} =
      TestCacheAdapter.start(%{
        url => %{etag: "\"abc123\"", last_modified: nil, body: fixture(:rss)}
      })

    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    {posts, log} =
      with_log(fn ->
        Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))
      end)

    assert [post] = posts
    assert post.title == "Sequences"
    assert log =~ "something went wrong while retrieving URL"
  end

  test "200 response with etag updates cache" do
    url = "https://www.theerlangelist.com/rss"
    {:ok, _} = TestCacheAdapter.start()
    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", "\"v1\"")
      |> Req.Test.html(fixture(:rss))
    end)

    Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

    cached = TestCacheAdapter.get(url)
    assert cached != nil
    assert cached.etag == "\"v1\""
    assert cached.body =~ "Sequences"
  end

  test "200 response without caching headers does not update cache" do
    url = "https://www.theerlangelist.com/rss"
    {:ok, _} = TestCacheAdapter.start()
    on_exit(fn -> TestCacheAdapter.stop() end)

    stub_feed(:rss)

    Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

    assert TestCacheAdapter.get(url) == nil
  end

  defp build_config(opts), do: struct!(Exoplanet.Config, opts)
end

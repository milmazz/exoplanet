defmodule Exoplanet.ParserCacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

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

  test "success: 304 Not Modified uses cached body" do
    url = "https://www.theerlangelist.com/rss"

    {:ok, _} =
      TestCacheAdapter.start(%{
        url => %{etag: "\"abc123\"", last_modified: nil, body: rss_feed()}
      })

    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Plug.Conn.send_resp(conn, 304, "")
    end)

    sources = %{url => %{name: "Saša Jurić"}}
    config = build_config(sources: sources)
    [post] = Exoplanet.build(config)

    assert post.title == "Sequences"
    assert post.feed_url == url
  end

  test "success: network error falls back to cached body" do
    url = "https://www.theerlangelist.com/rss"

    {:ok, _} =
      TestCacheAdapter.start(%{
        url => %{etag: "\"abc123\"", last_modified: nil, body: rss_feed()}
      })

    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    {posts, log} =
      with_log(fn ->
        sources = %{url => %{name: "Saša Jurić"}}
        config = build_config(sources: sources)
        Exoplanet.build(config)
      end)

    assert [post] = posts
    assert post.title == "Sequences"
    assert log =~ "something went wrong while retrieving URL"
  end

  test "success: 200 response with etag updates cache" do
    url = "https://www.theerlangelist.com/rss"
    {:ok, _} = TestCacheAdapter.start()
    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", "\"v1\"")
      |> Req.Test.html(rss_feed())
    end)

    sources = %{url => %{name: "Saša Jurić"}}
    config = build_config(sources: sources)
    Exoplanet.build(config)

    cached = TestCacheAdapter.get(url)
    assert cached != nil
    assert cached.etag == "\"v1\""
    assert cached.body =~ "Sequences"
  end

  test "success: 200 response without caching headers does not update cache" do
    url = "https://www.theerlangelist.com/rss"
    {:ok, _} = TestCacheAdapter.start()
    on_exit(fn -> TestCacheAdapter.stop() end)

    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, rss_feed())
    end)

    sources = %{url => %{name: "Saša Jurić"}}
    config = build_config(sources: sources)
    Exoplanet.build(config)

    assert TestCacheAdapter.get(url) == nil
  end

  defp build_config(opts) do
    default_opts = [
      owner_name: "John Doe",
      owner_email: "jdoe@example.com",
      name: "Exoplanet",
      link: "https://example.com",
      about: ""
    ]

    struct!(Exoplanet.Config, Keyword.merge(default_opts, opts))
  end

  defp rss_feed do
    """
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <atom:link href="http://theerlangelist.com/rss" rel="self" type="application/rss+xml" />
        <title>The Erlangelist</title>
        <description>(not only) Erlang related musings</description>
        <link>http://theerlangelist.com</link>

        <item>
          <title><![CDATA[Sequences]]></title>
          <link><![CDATA[http://theerlangelist.com//article/sequences]]></link>
          <pubDate>Mon, 14 Dec 20 00:00:00 +0000</pubDate>
          <description>
            <![CDATA[<h1>Sequences</h1>
          ]]>
          </description>
          <guid isPermaLink="true">http://theerlangelist.com//article/sequences</guid>
        </item>
      </channel>
    </rss>
    """
  end
end

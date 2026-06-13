defmodule Exoplanet.FetcherCacheTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Exoplanet.TestHelpers

  # In-memory cache adapter backed by an Agent. Implements Exoplanet.Cache so
  # it can be wired in via Application.put_env(:exoplanet, :cache_adapter, ...).
  # Started with `start_supervised!({TestCacheAdapter, entries})`, which links
  # it to the test supervisor and tears it down (and frees the registered
  # name) before the next test runs.
  defmodule TestCacheAdapter do
    @behaviour Exoplanet.Cache

    def child_spec(entries) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [entries]}}
    end

    def start_link(entries) do
      Agent.start_link(fn -> entries end, name: __MODULE__)
    end

    @impl Exoplanet.Cache
    def get(url), do: Agent.get(__MODULE__, &Map.get(&1, url))

    @impl Exoplanet.Cache
    def put(url, entry) do
      Agent.update(__MODULE__, &Map.put(&1, url, entry))
      :ok
    end
  end

  # Like TestCacheAdapter, but also implements the optional notification
  # callbacks, recording every call so tests can assert on them.
  defmodule NotifyingCacheAdapter do
    @behaviour Exoplanet.Cache

    def child_spec(entries) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [entries]}}
    end

    def start_link(entries) do
      Agent.start_link(fn -> %{entries: entries, notifications: []} end, name: __MODULE__)
    end

    def notifications do
      __MODULE__ |> Agent.get(& &1.notifications) |> Enum.reverse()
    end

    @impl Exoplanet.Cache
    def get(url), do: Agent.get(__MODULE__, &Map.get(&1.entries, url))

    @impl Exoplanet.Cache
    def put(url, entry) do
      Agent.update(__MODULE__, fn state -> put_in(state.entries[url], entry) end)
      :ok
    end

    @impl Exoplanet.Cache
    def on_success(url, status) do
      record({:success, url, status})
    end

    @impl Exoplanet.Cache
    def on_error(url, status, reason) do
      record({:error, url, status, reason})
    end

    defp record(notification) do
      Agent.update(__MODULE__, fn state ->
        update_in(state.notifications, &[notification | &1])
      end)

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

    start_supervised!(
      {TestCacheAdapter, %{url => %{etag: "\"abc123\"", last_modified: nil, body: fixture(:rss)}}}
    )

    Req.Test.stub(Exoplanet.Fetcher, fn conn ->
      Plug.Conn.send_resp(conn, 304, "")
    end)

    [post] = Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

    assert post.title == "Sequences"
    assert post.feed_url == url
  end

  test "network error falls back to cached body" do
    url = "https://www.theerlangelist.com/rss"

    start_supervised!(
      {TestCacheAdapter, %{url => %{etag: "\"abc123\"", last_modified: nil, body: fixture(:rss)}}}
    )

    Req.Test.stub(Exoplanet.Fetcher, fn conn ->
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
    start_supervised!({TestCacheAdapter, %{}})

    Req.Test.stub(Exoplanet.Fetcher, fn conn ->
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
    start_supervised!({TestCacheAdapter, %{}})

    stub_feed(:rss)

    Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

    assert TestCacheAdapter.get(url) == nil
  end

  describe "notification callbacks" do
    setup do
      Application.put_env(:exoplanet, :cache_adapter, NotifyingCacheAdapter)
      start_supervised!({NotifyingCacheAdapter, %{}})
      :ok
    end

    test "on_success/2 is called with 200 on a fresh fetch" do
      url = "https://www.theerlangelist.com/rss"
      stub_feed(:rss)

      Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

      assert NotifyingCacheAdapter.notifications() == [{:success, url, 200}]
    end

    test "on_success/2 is called with 304 when the cached body is reused" do
      url = "https://www.theerlangelist.com/rss"

      NotifyingCacheAdapter.put(url, %{
        etag: "\"abc123\"",
        last_modified: nil,
        body: fixture(:rss)
      })

      Req.Test.stub(Exoplanet.Fetcher, fn conn ->
        Plug.Conn.send_resp(conn, 304, "")
      end)

      Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))

      assert NotifyingCacheAdapter.notifications() == [{:success, url, 304}]
    end

    test "on_error/3 is called with the status for unexpected HTTP responses" do
      url = "https://www.theerlangelist.com/rss"

      Req.Test.stub(Exoplanet.Fetcher, fn conn ->
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      {_posts, log} =
        with_log(fn ->
          Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))
        end)

      assert NotifyingCacheAdapter.notifications() == [{:error, url, 500, "HTTP 500"}]
      assert log =~ "unexpected HTTP status 500"
    end

    test "on_error/3 is called with nil status for transport errors" do
      url = "https://www.theerlangelist.com/rss"

      Req.Test.stub(Exoplanet.Fetcher, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {_posts, log} =
        with_log(fn ->
          Exoplanet.build(build_config(sources: %{url => %{name: "Saša Jurić"}}))
        end)

      assert [{:error, ^url, nil, reason}] = NotifyingCacheAdapter.notifications()
      assert reason =~ "timeout"
      assert log =~ "something went wrong while retrieving URL"
    end
  end

  defp build_config(opts), do: struct!(Exoplanet.Config, opts)
end

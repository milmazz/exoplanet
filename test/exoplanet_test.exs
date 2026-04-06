defmodule ExoplanetTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  test "success: parses rss feeds" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:rss))
    end)

    sources = %{"https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.id == "http://theerlangelist.com//article/sequences"
    assert post.authors == ["Saša Jurić"]
    assert post.title == "Sequences"
    assert post.body =~ "<h1>Sequences"
    assert NaiveDateTime.compare(post.published, ~N[2020-12-14 00:00:00]) == :eq
    assert post.feed_url == "https://www.theerlangelist.com/rss"
  end

  test "success: parses atom feeds" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:atom))
    end)

    sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.authors == ["Milton Mazzarri"]
    assert post.title == "Oban: Testing your Workers and Configuration"

    assert post.id ==
             "https://milmazz.uno/article/2022/02/21/oban-testing-your-workers-and-configuration"

    assert post.body ==
             "In this article, I will continue talking about Oban, but I’ll focus on how to..."

    assert NaiveDateTime.compare(post.published, ~N[2022-02-21 00:00:00]) == :eq
    assert NaiveDateTime.compare(post.updated, ~N[2022-02-22 00:00:00]) == :eq

    assert post.summary == "Testing your Oban Workers and its configuration."
    assert post.feed_url == "https://milmazz.uno/atom.xml"
  end

  test "success: order the posts by published date in descending order" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      data = if conn.host == "milmazz.uno", do: feed(:atom), else: feed(:rss)
      Req.Test.html(conn, data)
    end)

    sources = %{
      "https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"},
      "https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}
    }

    config = build_config(sources: sources)
    posts = Exoplanet.build(config)
    assert posts == Enum.sort_by(posts, & &1.published, {:desc, Date})
  end

  test "success: in case publishing date is missing, use last update as fallback" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      data = """
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Example</title>
        <updated>2025-03-26T09:37:06+00:00</updated>
        <id>http://example.com</id>

        <entry>
          <title>title</title>
          <link href="http://example.com/title/"/>

          <author>
          <name>John Doe</name>
          </author>

          <updated>2025-03-25T00:00:00+00:00</updated>
          <id>some-id</id>
          <content>...</content>
        </entry>
      </feed>
      """

      Req.Test.html(conn, data)
    end)

    sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
    config = build_config(sources: sources)

    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.published
    assert Date.compare(post.published, post.updated) == :eq
  end

  test "success: parses categories from rss feeds" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:rss_with_categories))
    end)

    sources = %{"https://example.com/feed.rss" => %{name: "Example"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.categories == ["Elixir", "BEAM"]
  end

  test "error: emit logs when cannot parse an atom feed" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      data = """
      <?xml version="1.0" encoding="utf-8"?>
      """

      Req.Test.html(conn, data)
    end)

    {result, log} =
      with_log(fn ->
        sources = %{"https://example.com/atom.xml" => %{name: "John Doe"}}
        config = build_config(sources: sources)

        Exoplanet.build(config)
      end)

    assert result == []
    assert log =~ "something went wrong while parsing feed"
  end

  test "error: emit logs when cannot parse a rss feed" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      data = """
      <?xml version="1.0" encoding="utf-8"?>
      <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      """

      Req.Test.html(conn, data)
    end)

    {result, log} =
      with_log(fn ->
        sources = %{"https://example.com/feed.rss" => %{name: "John Doe"}}
        config = build_config(sources: sources)

        Exoplanet.build(config)
      end)

    assert result == []
    assert log =~ "something went wrong while parsing feed"
  end

  test "error: emit logs when cannot retrieve a source" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.transport_error(conn, :timeout)
    end)

    {result, log} =
      with_log(fn ->
        sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
        config = build_config(sources: sources)

        Exoplanet.build(config)
      end)

    assert result == []
    assert log =~ "something went wrong while retrieving URL"
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

  defp feed(:rss) do
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

  defp feed(:atom) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <generator uri="https://jekyllrb.com/" version="3.9.0">Jekyll</generator>
      <link href="https://milmazz.uno/atom.xml" rel="self" type="application/atom+xml" />
      <link href="https://milmazz.uno/" rel="alternate" type="text/html" />
      <updated>2022-02-21T18:48:10-06:00</updated>
      <id>https://milmazz.uno/atom.xml</id>
      <title type="html">milmazz</title>
      <subtitle>To teach is to learn twice. - Joseph Joubert</subtitle>
      <author>
        <name>Milton Mazzarri</name>
        <email>me@milmazz.uno</email>
      </author>
      <entry>
        <title type="html">Oban: Testing your Workers and Configuration</title>
        <link href="https://milmazz.uno/article/2022/02/21/oban-testing-your-workers-and-configuration/" rel="alternate" type="text/html" title="Oban: Testing your Workers and Configuration" />
        <published>2022-02-21T00:00:00-06:00</published>
        <updated>2022-02-22T00:00:00-06:00</updated>
        <id>https://milmazz.uno/article/2022/02/21/oban-testing-your-workers-and-configuration</id>
        <summary type="html"><![CDATA[Testing your Oban Workers and its configuration.]]></summary>
        <content type="html" xml:base="https://milmazz.uno/article/2022/02/21/oban-testing-your-workers-and-configuration/">In this article, I will continue talking about Oban, but I’ll focus on how to...</content>
      </entry>
    </feed>
    """
  end

  defp feed(:rss_with_categories) do
    """
    <rss version="2.0">
      <channel>
        <title>Example</title>
        <link>https://example.com</link>

        <item>
          <title>Post With Categories</title>
          <link>https://example.com/post</link>
          <pubDate>Mon, 14 Dec 20 00:00:00 +0000</pubDate>
          <description>Content here</description>
          <category>Elixir</category>
          <category>BEAM</category>
        </item>
      </channel>
    </rss>
    """
  end
end

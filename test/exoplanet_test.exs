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

  test "success: parses categories from atom feeds" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:atom_with_categories))
    end)

    sources = %{"https://example.com/atom.xml" => %{name: "Example"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.categories == ["Elixir", "BEAM"]
  end

  test "success: categories is nil when feed has no categories" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:atom))
    end)

    sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.categories == nil
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

  test "success: parses rss feeds without version attribute" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:rss_no_version))
    end)

    sources = %{"https://example.com/feed.rss" => %{name: "Author"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.title == "Post Without Version"
    assert post.id == "https://example.com/post-1"
  end

  test "success: parses rss 1.0 (rdf) feeds" do
    Req.Test.stub(Exoplanet.Parser, fn conn ->
      Req.Test.html(conn, feed(:rss1))
    end)

    sources = %{"https://example.com/rss1.rdf" => %{name: "Author"}}
    config = build_config(sources: sources)
    [%Exoplanet.Post{} = post] = Exoplanet.build(config)

    assert post.title == "RSS 1.0 Post"
    assert post.id == "https://example.com/rss1-post"
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

  describe "filters integration" do
    test "filters apply per-source before Enum.take(new_feed_items)" do
      url = "https://filters-test.example/feed.xml"

      atom = """
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>F</title>
        <id>tag:filters-test</id>
        <updated>2026-01-01T00:00:00Z</updated>
        <entry>
          <id>1</id><title>One</title>
          <updated>2026-01-01T00:00:00Z</updated>
          <published>2026-01-01T00:00:00Z</published>
          <content type="html">a</content>
          <category term="elixir"/>
        </entry>
        <entry>
          <id>2</id><title>Two</title>
          <updated>2026-01-02T00:00:00Z</updated>
          <published>2026-01-02T00:00:00Z</published>
          <content type="html">b</content>
          <category term="elixir"/>
        </entry>
        <entry>
          <id>3</id><title>Three</title>
          <updated>2026-01-03T00:00:00Z</updated>
          <published>2026-01-03T00:00:00Z</published>
          <content type="html">c</content>
          <category term="elixir"/>
        </entry>
        <entry>
          <id>4</id><title>Four</title>
          <updated>2026-01-04T00:00:00Z</updated>
          <published>2026-01-04T00:00:00Z</published>
          <content type="html">d</content>
          <category term="personal"/>
        </entry>
        <entry>
          <id>5</id><title>Five</title>
          <updated>2026-01-05T00:00:00Z</updated>
          <published>2026-01-05T00:00:00Z</published>
          <content type="html">e</content>
          <category term="elixir"/>
        </entry>
        <entry>
          <id>6</id><title>Six</title>
          <updated>2026-01-06T00:00:00Z</updated>
          <published>2026-01-06T00:00:00Z</published>
          <content type="html">f</content>
          <category term="elixir"/>
        </entry>
      </feed>
      """

      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.text(conn, atom)
      end)

      config = %Exoplanet.Config{
        name: "T",
        link: "https://t.example",
        owner_name: "T",
        owner_email: "t@example.com",
        about: "",
        sources: %{url => %{name: "F"}},
        new_feed_items: 4,
        items: 60,
        feed_timeout: 5,
        default_filters: %{
          allow_categories: ["elixir"],
          block_categories: [],
          strip_images: false,
          excerpt_length: nil
        }
      }

      posts = Exoplanet.build(config)

      # 5 entries match the allowlist (1, 2, 3, 5, 6); entry 4 (personal) does not.
      # If filtering ran AFTER Enum.take(4), we'd take entries 1-4 and then drop
      # entry 4 → only 3 surviving posts. Filter-before-take yields exactly 4.
      assert length(posts) == 4
      titles = Enum.map(posts, & &1.title)
      refute "Four" in titles
    end
  end

  describe "blank input handling" do
    test "rss: blank <author> falls back to the source's configured name" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, feed(:rss_blank_author))
      end)

      sources = %{"https://blank-author.example/feed" => %{name: "Source Name"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.authors == ["Source Name"]
    end

    test "atom: every blank <author><name>...</name></author> falls back to the source name" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, feed(:atom_blank_author))
      end)

      sources = %{"https://blank-author.example/feed.xml" => %{name: "Source Name"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.authors == ["Source Name"]
    end

    test "atom: empty <summary> is normalised to nil (so consumers fall back to body)" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, feed(:atom_empty_summary))
      end)

      sources = %{"https://empty-summary.example/feed.xml" => %{name: "S"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.summary == nil
      assert post.body =~ "Body content"
    end
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

  defp feed(:atom_with_categories) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Example</title>
      <id>https://example.com/atom.xml</id>
      <updated>2024-01-01T00:00:00Z</updated>

      <entry>
        <title>Post With Categories</title>
        <link href="https://example.com/post"/>
        <id>https://example.com/post</id>
        <published>2024-01-01T00:00:00Z</published>
        <updated>2024-01-01T00:00:00Z</updated>
        <author><name>Example Author</name></author>
        <category term="Elixir"/>
        <category term="BEAM"/>
        <content>Content here</content>
      </entry>
    </feed>
    """
  end

  defp feed(:rss_no_version) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel>
        <title>Example</title>
        <link>https://example.com</link>
        <item>
          <title>Post Without Version</title>
          <link>https://example.com/post-1</link>
          <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
          <description>Content here</description>
        </item>
      </channel>
    </rss>
    """
  end

  defp feed(:rss1) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
             xmlns="http://purl.org/rss/1.0/"
             xmlns:dc="http://purl.org/dc/elements/1.1/">
      <channel rdf:about="https://example.com/rss1.rdf">
        <title>RSS 1.0 Feed</title>
        <link>https://example.com</link>
        <items>
          <rdf:Seq>
            <rdf:li rdf:resource="https://example.com/rss1-post"/>
          </rdf:Seq>
        </items>
      </channel>
      <item rdf:about="https://example.com/rss1-post">
        <title>RSS 1.0 Post</title>
        <link>https://example.com/rss1-post</link>
        <description>RSS 1.0 content</description>
        <dc:date>2024-01-01T00:00:00Z</dc:date>
      </item>
    </rdf:RDF>
    """
  end

  defp feed(:rss_blank_author) do
    """
    <rss version="2.0">
      <channel>
        <title>Blank Author</title>
        <link>https://blank-author.example</link>
        <item>
          <title>Post With Blank Author</title>
          <link>https://blank-author.example/post-1</link>
          <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
          <author>   </author>
          <description>Body</description>
        </item>
      </channel>
    </rss>
    """
  end

  defp feed(:atom_blank_author) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Blank Author</title>
      <id>tag:blank-author</id>
      <updated>2024-01-01T00:00:00Z</updated>
      <entry>
        <id>https://blank-author.example/post-1</id>
        <title>Post With Blank Author Names</title>
        <updated>2024-01-01T00:00:00Z</updated>
        <published>2024-01-01T00:00:00Z</published>
        <author><name></name></author>
        <author><name>   </name></author>
        <content type="html">Body</content>
      </entry>
    </feed>
    """
  end

  defp feed(:atom_empty_summary) do
    """
    <?xml version="1.0" encoding="utf-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Empty Summary</title>
      <id>tag:empty-summary</id>
      <updated>2024-01-01T00:00:00Z</updated>
      <entry>
        <id>https://empty-summary.example/post-1</id>
        <title>Post With Empty Summary</title>
        <updated>2024-01-01T00:00:00Z</updated>
        <published>2024-01-01T00:00:00Z</published>
        <author><name>Alice</name></author>
        <summary></summary>
        <content type="html">Body content here</content>
      </entry>
    </feed>
    """
  end
end

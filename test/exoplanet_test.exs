defmodule ExoplanetTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Exoplanet.TestHelpers

  describe "RSS parsing" do
    test "parses rss feeds" do
      stub_feed(:rss)

      sources = %{"https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.id == "http://theerlangelist.com//article/sequences"
      assert post.authors == ["Saša Jurić"]
      assert post.title == "Sequences"
      assert post.body =~ "<h1>Sequences"
      assert NaiveDateTime.compare(post.published, ~N[2020-12-14 00:00:00]) == :eq
      assert post.feed_url == "https://www.theerlangelist.com/rss"
    end

    test "parses rss feeds without version attribute" do
      stub_feed(:rss_no_version)

      sources = %{"https://example.com/feed.rss" => %{name: "Author"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "Post Without Version"
      assert post.id == "https://example.com/post-1"
    end

    test "parses RSS 1.0 (RDF) feeds with <dc:date>" do
      stub_feed(:rss1)

      sources = %{"https://example.com/rss1.rdf" => %{name: "Author"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "RSS 1.0 Post"
      assert post.id == "https://example.com/rss1-post"
      assert NaiveDateTime.compare(post.published, ~N[2024-01-01 00:00:00]) == :eq
    end

    test "prefers <content:encoded> over <description> when both are present" do
      stub_feed(:rss_with_content_encoded)

      sources = %{"https://content-encoded.example/feed" => %{name: "S"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.body =~ "Full article HTML"
      refute post.body =~ "Short snippet"
    end

    test "falls back to <description> when <content:encoded> is absent" do
      stub_feed(:rss)

      sources = %{"https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.body =~ "<h1>Sequences"
    end
  end

  describe "Atom parsing" do
    test "parses atom feeds" do
      stub_feed(:atom)

      sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

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

    test "falls back to <updated> when <published> is missing" do
      stub_feed(:atom_published_missing)

      sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.published
      assert Date.compare(post.published, post.updated) == :eq
    end

    test "atom: falls back to alternate <link href> when <id> is not an http(s) URL" do
      # Regression: Bridgetown / Jekyll-style feeds can emit a non-resolvable
      # `repo://...` scheme inside <id>. We must fall back to the alternate
      # <link href rel="alternate" type="text/html"> so consumers render a
      # working URL, not a bare guid that surfaces as a broken link.
      stub_feed(:atom_non_url_id)

      sources = %{"https://katafrakt.example/feed.xml" => %{name: "katafrakt"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.id == "https://katafrakt.example/2026/01/03/elixir-head-with-mise/"
    end

    test "empty <summary> is normalised to nil so consumers fall back to body" do
      stub_feed(:atom_empty_summary)

      sources = %{"https://empty-summary.example/feed.xml" => %{name: "S"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.summary == nil
      assert post.body =~ "Body content"
    end
  end

  describe "categories" do
    test "extracts categories from rss feeds" do
      stub_feed(:rss_with_categories)

      sources = %{"https://example.com/feed.rss" => %{name: "Example"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.categories == ["Elixir", "BEAM"]
    end

    test "extracts categories from atom feeds" do
      stub_feed(:atom_with_categories)

      sources = %{"https://example.com/atom.xml" => %{name: "Example"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.categories == ["Elixir", "BEAM"]
    end

    test "categories is nil when feed has no categories" do
      stub_feed(:atom)

      sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.categories == nil
    end

    test "trims trailing commas/semicolons and surrounding whitespace from categories" do
      # Regression: erlang.org/news.xml emits `<category term="otp,"/>` etc;
      # the trailing comma made allow-list matching fail under plain
      # case-insensitive equality. Categories must be normalised at
      # extraction time so both filtering and persisted post records
      # see the canonical "OTP" form.
      stub_feed(:atom_with_trailing_comma_categories)

      sources = %{"https://example.com/feed.xml" => %{name: "Example"}}

      filters = %{
        allow_categories: ["otp"],
        block_categories: [],
        strip_images: false,
        excerpt_length: nil
      }

      [%Exoplanet.Post{} = post] =
        Exoplanet.build(build_config(sources: sources, default_filters: filters))

      assert post.categories == ["release", "OTP", "28.5"]
    end
  end

  describe "blank authors" do
    test "rss: blank <author> falls back to the source's configured name" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
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
        """)
      end)

      sources = %{"https://blank-author.example/feed" => %{name: "Source Name"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.authors == ["Source Name"]
    end

    test "atom: every blank <author><name>...</name></author> falls back to the source name" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
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
        """)
      end)

      sources = %{"https://blank-author.example/feed.xml" => %{name: "Source Name"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.authors == ["Source Name"]
    end
  end

  describe "ordering" do
    test "per-feed cap keeps the chronologically newest entries, not document-order entries" do
      # Regression: `Exoplanet.build/1` previously called
      # `Enum.take(config.new_feed_items)` on the post-filter list while
      # the entries were still in feed-document order. For feeds that
      # don't list entries newest-first, the older entries got picked
      # and the genuinely-recent ones were silently dropped before the
      # global merge-sort.
      stub_feed(:atom_unordered)

      sources = %{"https://unordered.example/feed.xml" => %{name: "U"}}

      posts =
        Exoplanet.build(%Exoplanet.Config{
          sources: sources,
          new_feed_items: 2,
          items: 60,
          feed_timeout: 5,
          default_filters: %{}
        })

      assert length(posts) == 2

      titles = Enum.map(posts, & &1.title)
      assert titles == ["Newest Third", "Mid Fourth"]
    end

    test "orders posts by published date in descending order" do
      stub_feeds(%{
        "milmazz.uno" => :atom,
        "www.theerlangelist.com" => :rss
      })

      sources = %{
        "https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"},
        "https://www.theerlangelist.com/rss" => %{name: "Saša Jurić"}
      }

      posts = Exoplanet.build(build_config(sources: sources))
      assert posts == Enum.sort_by(posts, & &1.published, {:desc, Date})
    end
  end

  describe "errors" do
    test "logs when an atom feed fails to parse" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, ~s(<?xml version="1.0" encoding="utf-8"?>\n))
      end)

      {result, log} =
        with_log(fn ->
          sources = %{"https://example.com/atom.xml" => %{name: "John Doe"}}
          Exoplanet.build(build_config(sources: sources))
        end)

      assert result == []
      assert log =~ "parse failed"
    end

    test "logs when an rss feed fails to parse" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
        """)
      end)

      {result, log} =
        with_log(fn ->
          sources = %{"https://example.com/feed.rss" => %{name: "John Doe"}}
          Exoplanet.build(build_config(sources: sources))
        end)

      assert result == []
      assert log =~ "parse failed"
    end

    test "logs when a source can't be retrieved" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.transport_error(conn, :timeout)
      end)

      {result, log} =
        with_log(fn ->
          sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}
          Exoplanet.build(build_config(sources: sources))
        end)

      assert result == []
      assert log =~ "something went wrong while retrieving URL"
    end
  end

  describe "filters integration" do
    test "filters apply per-source before Enum.take(new_feed_items)" do
      stub_feed(:atom_six_entries_for_filters)

      posts =
        Exoplanet.build(
          filter_test_config(%{
            allow_categories: ["elixir"],
            block_categories: [],
            strip_images: false,
            excerpt_length: nil,
            sanitize_html: false,
            drop_tags: [],
            drop_attrs: []
          })
        )

      # 5 entries match the allowlist (1, 2, 3, 5, 6); entry 4 (personal) does not.
      # If filtering ran AFTER Enum.take(4), we'd take entries 1-4 and then drop
      # entry 4 → only 3 surviving posts. Filter-before-take yields exactly 4.
      assert length(posts) == 4
      titles = Enum.map(posts, & &1.title)
      refute "Four" in titles
    end

    test "fills missing keys from library defaults when default_filters is partial" do
      stub_feed(:atom_six_entries_for_filters)

      # Omits sanitize_html / drop_tags / drop_attrs. Before the fix
      # `Filters.apply/2` raised KeyError on `filters.drop_tags` when the
      # sanitize? branch ran with `sanitize_html` defaulted to true.
      posts =
        Exoplanet.build(
          filter_test_config(%{
            allow_categories: ["elixir"],
            block_categories: [],
            strip_images: false,
            excerpt_length: nil
          })
        )

      assert length(posts) == 4
      refute "Four" in Enum.map(posts, & &1.title)
    end

    test "fills missing list-typed keys (allow/block_categories) from library defaults" do
      stub_feed(:atom_six_entries_for_filters)

      # Omits both list-typed keys; library defaults are `[]` (allow all,
      # block none), so the "personal" entry is no longer filtered out.
      posts =
        Exoplanet.build(
          filter_test_config(%{
            strip_images: false,
            excerpt_length: nil,
            sanitize_html: false,
            drop_tags: [],
            drop_attrs: []
          })
        )

      titles = Enum.map(posts, & &1.title)
      assert "Four" in titles
    end

    test "applies library default sanitize_html when user omits it" do
      url = "https://sanitize-test.example/feed.xml"

      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>S</title>
          <id>tag:sanitize-test</id>
          <updated>2026-01-01T00:00:00Z</updated>
          <entry>
            <id>1</id><title>Has script</title>
            <updated>2026-01-01T00:00:00Z</updated>
            <published>2026-01-01T00:00:00Z</published>
            <content type="html">&lt;p&gt;safe&lt;/p&gt;&lt;script&gt;alert(1)&lt;/script&gt;</content>
          </entry>
        </feed>
        """)
      end)

      [post] =
        Exoplanet.build(%Exoplanet.Config{
          sources: %{url => %{name: "S"}},
          feed_timeout: 5,
          default_filters: %{}
        })

      refute post.body =~ "<script"
      refute post.body =~ "alert(1)"
      assert post.body =~ "safe"
    end
  end

  describe "dc:creator" do
    test "rss: uses <dc:creator> when <author> is absent" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        data = """
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>DC Creator Test</title>
            <link>https://dc-creator.example</link>
            <item>
              <title>Post With DC Creator</title>
              <link>https://dc-creator.example/post-1</link>
              <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
              <dc:creator>Alice</dc:creator>
              <description>Body</description>
            </item>
          </channel>
        </rss>
        """

        Req.Test.html(conn, data)
      end)

      sources = %{"https://dc-creator.example/feed" => %{name: "Source Name"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.authors == ["Alice"]
    end

    test "rss: prefers <dc:creator> over <author> when both are present" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        data = """
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>DC Creator Test</title>
            <link>https://dc-creator.example</link>
            <item>
              <title>Post With Both Author Fields</title>
              <link>https://dc-creator.example/post-2</link>
              <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
              <dc:creator>Alice</dc:creator>
              <author>noreply@example.com</author>
              <description>Body</description>
            </item>
          </channel>
        </rss>
        """

        Req.Test.html(conn, data)
      end)

      sources = %{"https://dc-creator.example/feed" => %{name: "Source Name"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.authors == ["Alice"]
    end

    test "rss: collects multiple <dc:creator> entries in order" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        data = """
        <rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>DC Creator Test</title>
            <link>https://dc-creator.example</link>
            <item>
              <title>Post With Multiple Creators</title>
              <link>https://dc-creator.example/post-3</link>
              <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
              <dc:creator>Alice</dc:creator>
              <dc:creator>Bob</dc:creator>
              <description>Body</description>
            </item>
          </channel>
        </rss>
        """

        Req.Test.html(conn, data)
      end)

      sources = %{"https://dc-creator.example/feed" => %{name: "Source Name"}}
      config = build_config(sources: sources)
      [%Exoplanet.Post{} = post] = Exoplanet.build(config)

      assert post.authors == ["Alice", "Bob"]
    end
  end

  describe "malformed dates" do
    test "rss: unparseable <pubDate> drops only the bad post; siblings survive" do
      stub_feed(:rss_bad_date)

      sources = %{"https://bad-date.example/feed.rss" => %{name: "Bad Date"}}

      {posts, log} =
        with_log(fn -> Exoplanet.build(build_config(sources: sources)) end)

      assert [%Exoplanet.Post{} = post] = posts
      assert post.title == "Good post"
      assert NaiveDateTime.compare(post.published, ~N[2026-04-01 00:00:00]) == :eq
      assert log =~ "unparseable RFC822 date"
      assert log =~ "totally not a date"
      assert log =~ "skipping post"
    end

    test "rss: missing <pubDate> drops the post (no date = not sortable)" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
        <?xml version="1.0" encoding="utf-8"?>
        <rss version="2.0">
          <channel>
            <title>No Date</title>
            <link>https://no-date.example</link>
            <description>x</description>
            <item>
              <title>No date at all</title>
              <link>https://no-date.example/no</link>
              <author>a@b.c (A)</author>
              <description>body</description>
            </item>
            <item>
              <title>Has date</title>
              <link>https://no-date.example/yes</link>
              <author>a@b.c (A)</author>
              <pubDate>Wed, 01 Apr 2026 00:00:00 +0000</pubDate>
              <description>body</description>
            </item>
          </channel>
        </rss>
        """)
      end)

      sources = %{"https://no-date.example/feed.rss" => %{name: "No Date"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "Has date"
    end

    test "atom: entry with neither <published> nor <updated> is dropped" do
      Req.Test.stub(Exoplanet.Parser, fn conn ->
        Req.Test.html(conn, """
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <title>Mix</title>
          <id>tag:no-dates</id>
          <updated>2026-04-01T00:00:00Z</updated>
          <entry>
            <id>https://no-dates.example/no</id>
            <title>No dates at all</title>
            <author><name>Alice</name></author>
            <content type="html">body</content>
          </entry>
          <entry>
            <id>https://no-dates.example/upd</id>
            <title>Has updated</title>
            <updated>2026-04-01T00:00:00Z</updated>
            <author><name>Alice</name></author>
            <content type="html">body</content>
          </entry>
        </feed>
        """)
      end)

      sources = %{"https://no-dates.example/feed.xml" => %{name: "Mix"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "Has updated"
    end
  end

  defp build_config(opts), do: struct!(Exoplanet.Config, opts)

  defp filter_test_config(default_filters) do
    %Exoplanet.Config{
      sources: %{"https://filters-test.example/feed.xml" => %{name: "F"}},
      new_feed_items: 4,
      items: 60,
      feed_timeout: 5,
      default_filters: default_filters
    }
  end
end

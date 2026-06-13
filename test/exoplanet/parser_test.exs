defmodule Exoplanet.ParserTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Exoplanet.TestHelpers

  alias Exoplanet.Parser
  alias Exoplanet.Post

  @url "https://example.test/feed"
  @name "Source Name"

  describe "parse/3 with RSS bodies (no HTTP stub)" do
    test "parses an RSS 2.0 feed into Post structs" do
      posts = Parser.parse(fixture(:rss), @url, @name)

      assert [%Post{} | _] = posts
      assert Enum.all?(posts, &(&1.feed_url == @url))
      assert Enum.all?(posts, &match?(%NaiveDateTime{}, &1.published))
    end

    test "parses RSS 1.0 (rdf:RDF) bodies" do
      assert [%Post{} | _] = Parser.parse(fixture(:rss1), @url, @name)
    end

    test "parses RSS without a version attribute" do
      assert [%Post{} | _] = Parser.parse(fixture(:rss_no_version), @url, @name)
    end

    test "prefers <content:encoded> over <description>" do
      [post | _] = Parser.parse(fixture(:rss_with_content_encoded), @url, @name)
      # The fixture's <content:encoded> holds "<p>Full article HTML</p>" while
      # <description> holds "Short snippet"; preferring content:encoded means the
      # body carries the former and never the latter.
      assert post.body =~ "Full article HTML"
      refute post.body =~ "Short snippet"
    end

    test "falls back to the source name when <author> is blank" do
      body = """
      <rss version="2.0"><channel>
        <title>T</title><link>https://example.test</link>
        <item>
          <title>P</title><link>https://example.test/p</link>
          <pubDate>Mon, 14 Dec 2020 00:00:00 +0000</pubDate>
          <author>   </author><description>Body</description>
        </item>
      </channel></rss>
      """

      assert [%Post{authors: [@name]}] = Parser.parse(body, @url, @name)
    end

    test "skips an entry with an unparseable date and logs a warning, keeping valid siblings" do
      # rss_bad_date.xml has two items: one with an unparseable <pubDate>
      # ("totally not a date") and one valid item ("Good post"). The bad item is
      # dropped, the valid sibling is kept, and a warning is logged.
      {posts, log} =
        with_log(fn -> Parser.parse(fixture(:rss_bad_date), @url, @name) end)

      assert [%Post{} = good] = posts
      assert good.title == "Good post"
      assert match?(%NaiveDateTime{}, good.published)
      refute Enum.any?(posts, &(&1.title == "Post with bad date"))
      assert log =~ "unparseable"
    end
  end

  describe "parse/3 with Atom bodies (no HTTP stub)" do
    test "parses an Atom feed into Post structs" do
      posts = Parser.parse(fixture(:atom), @url, @name)

      assert [%Post{} | _] = posts
      assert Enum.all?(posts, &(&1.feed_url == @url))
    end

    test "falls back to <updated> when <published> is missing" do
      # atom_published_missing.xml's entry omits <published> but supplies
      # <updated>; the parser falls back to <updated>, so the post is kept with a
      # real NaiveDateTime published value (entries with neither would be dropped).
      posts = Parser.parse(fixture(:atom_published_missing), @url, @name)
      assert [%Post{} | _] = posts
      assert Enum.all?(posts, &match?(%NaiveDateTime{}, &1.published))
    end

    test "cleans trailing-comma categories" do
      [post | _] = Parser.parse(fixture(:atom_with_trailing_comma_categories), @url, @name)
      assert post.categories == ["release", "otp", "28.5"]
    end

    test "detects Atom when the literal <rss appears only inside entry content" do
      # Feed-type detection must look at the root element, not any substring.
      # An Atom entry that merely mentions "<rss" / "<rdf:RDF" in its content
      # must still be parsed as Atom (the old substring check misfired here).
      body = """
      <?xml version="1.0" encoding="utf-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <id>urn:example:feed</id>
        <title>Example</title>
        <entry>
          <title>A post about feed formats</title>
          <link href="https://example.test/p1" rel="alternate" type="text/html" />
          <published>2022-02-21T00:00:00Z</published>
          <id>https://example.test/p1</id>
          <content type="html"><![CDATA[I built an <rss> and <rdf:RDF> reader.]]></content>
        </entry>
      </feed>
      """

      assert [%Post{title: "A post about feed formats"}] = Parser.parse(body, @url, @name)
    end
  end
end

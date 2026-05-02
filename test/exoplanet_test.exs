defmodule ExoplanetTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Exoplanet.TestSupport

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
  end

  describe "blank authors" do
    test "rss: blank <author> falls back to the source's configured name" do
      stub_feed(:rss_blank_author)

      sources = %{"https://blank-author.example/feed" => %{name: "Source Name"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.authors == ["Source Name"]
    end

    test "atom: every blank <author><name>...</name></author> falls back to the source name" do
      stub_feed(:atom_blank_author)

      sources = %{"https://blank-author.example/feed.xml" => %{name: "Source Name"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.authors == ["Source Name"]
    end
  end

  describe "ordering" do
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
      stub_body(~s(<?xml version="1.0" encoding="utf-8"?>\n))

      {result, log} =
        with_log(fn ->
          sources = %{"https://example.com/atom.xml" => %{name: "John Doe"}}
          Exoplanet.build(build_config(sources: sources))
        end)

      assert result == []
      assert log =~ "parse failed"
    end

    test "logs when an rss feed fails to parse" do
      stub_body(
        ~s(<?xml version="1.0" encoding="utf-8"?>\n<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">\n)
      )

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

      url = "https://filters-test.example/feed.xml"

      config = %Exoplanet.Config{
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
      stub_feed(:rss_no_pubdate)

      sources = %{"https://no-date.example/feed.rss" => %{name: "No Date"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "Has date"
    end

    test "atom: entry with neither <published> nor <updated> is dropped" do
      stub_feed(:atom_no_dates)

      sources = %{"https://no-dates.example/feed.xml" => %{name: "Mix"}}
      [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

      assert post.title == "Has updated"
    end
  end

  defp build_config(opts), do: struct!(Exoplanet.Config, opts)
end

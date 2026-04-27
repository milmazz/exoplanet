defmodule Exoplanet.FiltersTest do
  use ExUnit.Case, async: true

  alias Exoplanet.Filters

  @defaults %{
    allow_categories: ["elixir", "erlang"],
    block_categories: ["personal"],
    strip_images: false,
    excerpt_length: 500
  }

  describe "merge/2" do
    test "returns defaults when per_feed is nil" do
      assert Filters.merge(@defaults, nil) == @defaults
    end

    test "returns defaults when per_feed is empty" do
      assert Filters.merge(@defaults, %{}) == @defaults
    end

    test "per_feed allow_categories replaces default (does not union)" do
      result = Filters.merge(@defaults, %{allow_categories: ["gleam"]})
      assert result.allow_categories == ["gleam"]
      assert result.block_categories == ["personal"]
    end

    test "per_feed empty allow_categories opts out of the default allowlist" do
      result = Filters.merge(@defaults, %{allow_categories: []})
      assert result.allow_categories == []
      assert result.block_categories == ["personal"]
    end

    test "per_feed block_categories replaces default" do
      result = Filters.merge(@defaults, %{block_categories: ["food"]})
      assert result.block_categories == ["food"]
      assert result.allow_categories == ["elixir", "erlang"]
    end

    test "per_feed strip_images overrides default" do
      result = Filters.merge(@defaults, %{strip_images: true})
      assert result.strip_images == true
    end

    test "per_feed excerpt_length overrides default" do
      result = Filters.merge(@defaults, %{excerpt_length: 200})
      assert result.excerpt_length == 200
    end

    test "per_feed nil values leave the default in place" do
      result =
        Filters.merge(@defaults, %{
          strip_images: nil,
          excerpt_length: nil,
          allow_categories: nil,
          block_categories: nil
        })

      assert result == @defaults
    end
  end

  describe "apply/2 — category filtering" do
    defp post(opts) do
      %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: "<p>body</p>",
        categories: opts[:categories],
        published: nil,
        summary: opts[:summary]
      }
    end

    @no_filters %{
      allow_categories: [],
      block_categories: [],
      strip_images: false,
      excerpt_length: nil
    }

    test "no filters: keeps all posts" do
      posts = [post(categories: ["elixir"]), post(categories: nil)]
      assert Filters.apply(posts, @no_filters) == posts
    end

    test "allow_categories: keeps posts with at least one matching category" do
      filters = %{@no_filters | allow_categories: ["elixir", "erlang"]}
      keep = post(categories: ["erlang", "otp"])
      drop = post(categories: ["food"])

      assert Filters.apply([keep, drop], filters) == [keep]
    end

    test "allow_categories: drops posts whose categories are nil" do
      filters = %{@no_filters | allow_categories: ["elixir"]}
      assert Filters.apply([post(categories: nil)], filters) == []
    end

    test "allow_categories: comparison is case-insensitive" do
      filters = %{@no_filters | allow_categories: ["Elixir"]}

      assert Filters.apply([post(categories: ["elixir"])], filters) ==
               [post(categories: ["elixir"])]
    end

    test "block_categories: drops posts with any matching category" do
      filters = %{@no_filters | block_categories: ["personal"]}
      keep = post(categories: ["elixir"])
      drop = post(categories: ["elixir", "personal"])

      assert Filters.apply([keep, drop], filters) == [keep]
    end

    test "block_categories: posts with nil categories pass" do
      filters = %{@no_filters | block_categories: ["personal"]}

      assert Filters.apply([post(categories: nil)], filters) ==
               [post(categories: nil)]
    end

    test "block_categories: comparison is case-insensitive" do
      filters = %{@no_filters | block_categories: ["Personal"]}
      assert Filters.apply([post(categories: ["personal"])], filters) == []
    end

    test "allow + block combined: post must match allow AND not match block" do
      filters = %{@no_filters | allow_categories: ["elixir"], block_categories: ["draft"]}
      keep = post(categories: ["elixir"])
      drop_no_match = post(categories: ["food"])
      drop_blocked = post(categories: ["elixir", "draft"])

      assert Filters.apply([keep, drop_no_match, drop_blocked], filters) == [keep]
    end
  end

  describe "apply/2 — strip_images" do
    @strip %{
      allow_categories: [],
      block_categories: [],
      strip_images: true,
      excerpt_length: nil
    }

    test "replaces <img alt=\"X\" src=\"Y\"> with <a href=\"Y\">X</a> in body" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: ~s(<p>before <img alt="cat" src="https://i.example/cat.png"> after</p>),
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      assert result.body =~ ~s(<a href="https://i.example/cat.png">cat</a>)
      refute result.body =~ "<img"
    end

    test "drops images that have no alt attribute" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: ~s(<p>before<img src="https://i.example/cat.png">after</p>),
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      refute result.body =~ "<img"
      refute result.body =~ "<a href"
    end

    test "image with no src renders alt as plain text" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: ~s(<p>before <img alt="logo"> after</p>),
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      refute result.body =~ "<img"
      refute result.body =~ "<a "
      assert result.body =~ "logo"
    end

    test "applies the same transformation to summary when present" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: "<p>body</p>",
        categories: nil,
        published: nil,
        summary: ~s(<p><img alt="x" src="https://e/x.png"></p>)
      }

      [result] = Filters.apply([post], @strip)
      assert result.summary =~ ~s(<a href="https://e/x.png">x</a>)
    end

    test "strip_images: false leaves images intact" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: ~s(<p><img alt="x" src="https://e/x.png"></p>),
        categories: nil,
        published: nil,
        summary: nil
      }

      filters = %{@strip | strip_images: false}
      [result] = Filters.apply([post], filters)
      assert result.body =~ "<img"
    end

    test "leaves nil body and summary alone" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: nil,
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      assert result.body == nil
      assert result.summary == nil
    end

    test "preserves image-free body byte-identical" do
      html = "<p>plain & simple <br> text</p>"

      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: html,
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      assert result.body == html
    end

    test "rewrites images nested inside other containers" do
      post = %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["Alice"],
        title: "T",
        body: ~s(<div><figure><img alt="x" src="https://e/x.png"></figure></div>),
        categories: nil,
        published: nil,
        summary: nil
      }

      [result] = Filters.apply([post], @strip)
      assert result.body =~ ~s(<a href="https://e/x.png">x</a>)
      refute result.body =~ "<img"
      assert result.body =~ "<figure"
      assert result.body =~ "<div"
    end
  end

  describe "apply/2 — excerpt_length" do
    @excerpt_filters %{
      allow_categories: [],
      block_categories: [],
      strip_images: false,
      excerpt_length: 30
    }

    defp long_post(body, summary) do
      %Exoplanet.Post{
        id: "1",
        feed_url: "https://example.com/feed",
        authors: ["A"],
        title: "T",
        body: body,
        categories: nil,
        published: nil,
        summary: summary
      }
    end

    test "summary already shorter than excerpt_length is left untouched" do
      post = long_post("<p>full body</p>", "short")
      [result] = Filters.apply([post], @excerpt_filters)
      assert result.summary == "short"
    end

    test "summary longer than excerpt_length is replaced with truncated text" do
      summary = "<p>" <> String.duplicate("word ", 50) <> "</p>"
      post = long_post("<p>body</p>", summary)
      [result] = Filters.apply([post], @excerpt_filters)
      assert String.length(result.summary) <= 30
      assert String.ends_with?(result.summary, "…")
    end

    test "summary absent: a summary is generated from body" do
      body = "<p>" <> String.duplicate("hello ", 20) <> "</p>"
      post = long_post(body, nil)
      [result] = Filters.apply([post], @excerpt_filters)
      assert is_binary(result.summary)
      assert String.length(result.summary) <= 30
      assert String.ends_with?(result.summary, "…")
    end

    test "body is never modified by excerpt_length" do
      body = "<p>" <> String.duplicate("hello ", 20) <> "</p>"
      post = long_post(body, nil)
      [result] = Filters.apply([post], @excerpt_filters)
      assert result.body == body
    end

    test "excerpt_length: nil leaves summary unchanged" do
      filters = %{@excerpt_filters | excerpt_length: nil}
      summary = String.duplicate("word ", 50)
      post = long_post("<p>body</p>", summary)
      [result] = Filters.apply([post], filters)
      assert result.summary == summary
    end

    test "truncation breaks at the last whitespace before the limit" do
      filters = %{@excerpt_filters | excerpt_length: 10}
      post = long_post("<p>aaa bbb ccc ddd eee</p>", nil)
      [result] = Filters.apply([post], filters)
      assert String.length(result.summary) <= 10
      assert String.ends_with?(result.summary, "…")
      prefix = String.replace_trailing(result.summary, "…", "") |> String.trim_trailing()
      assert prefix == "" or Regex.match?(~r/^\w+( \w+)*$/, prefix)
    end

    test "truncates multi-byte UTF-8 content at correct grapheme boundary" do
      filters = %{@excerpt_filters | excerpt_length: 11}
      post = long_post("<p>你好 abc def ghi</p>", nil)
      [result] = Filters.apply([post], filters)
      assert String.length(result.summary) <= 11
      assert String.ends_with?(result.summary, "…")
      # Verify break occurred at a whitespace position — prefix must end at
      # a word boundary, not mid-word.
      prefix = String.replace_trailing(result.summary, "…", "") |> String.trim_trailing()

      # Expected: "你好 abc" (or shorter), not "你好 abc def" (over budget) or "你" (no whitespace break)
      refute String.ends_with?(prefix, "d")
      refute String.ends_with?(prefix, "de")
      refute String.ends_with?(prefix, "def")
    end

    test "returns nil summary when body has no extractable text" do
      filters = %{@excerpt_filters | excerpt_length: 100}
      # Body with only an image and no text content — html_to_text yields "".
      post = long_post(~s(<p><img src="https://e/x.png"></p>), nil)
      [result] = Filters.apply([post], filters)

      # nil (not "") so consumers using `summary || body` fall back to body.
      assert result.summary == nil
    end

    test "html-escapes the generated excerpt so consumers can render with raw/1" do
      filters = %{@excerpt_filters | excerpt_length: 200}

      body = ~s(<p>Code example: <pre>&lt;div class="x"&gt;hello&lt;/div&gt;</pre></p>)
      post = long_post(body, nil)
      [result] = Filters.apply([post], filters)

      # `LazyHTML.text/1` decodes `&lt;` / `&gt;` back to `<` / `>` — those
      # would break the consumer's layout if not re-escaped before rendering.
      refute result.summary =~ "<div"
      refute result.summary =~ "</div>"
      assert result.summary =~ "&lt;div"
      assert result.summary =~ "&lt;/div&gt;"
    end
  end
end

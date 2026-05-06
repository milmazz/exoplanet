defmodule Exoplanet.FiltersTest do
  use ExUnit.Case, async: true

  alias Exoplanet.Filters

  describe "merge/2" do
    # Populated default filter map used by these tests; co-located here because
    # only the merge/2 tests need it (the rest exercise overrides on top of an
    # empty map via filters/1).
    defp merge_defaults do
      filters(
        allow_categories: ["elixir", "erlang"],
        block_categories: ["personal"],
        excerpt_length: 500
      )
    end

    test "returns defaults when per_feed is nil" do
      assert Filters.merge(merge_defaults(), nil) == merge_defaults()
    end

    test "returns defaults when per_feed is empty" do
      assert Filters.merge(merge_defaults(), %{}) == merge_defaults()
    end

    test "per_feed allow_categories replaces default (does not union)" do
      result = Filters.merge(merge_defaults(), %{allow_categories: ["gleam"]})
      assert result.allow_categories == ["gleam"]
      assert result.block_categories == ["personal"]
    end

    test "per_feed empty allow_categories opts out of the default allowlist" do
      result = Filters.merge(merge_defaults(), %{allow_categories: []})
      assert result.allow_categories == []
      assert result.block_categories == ["personal"]
    end

    test "per_feed block_categories replaces default" do
      result = Filters.merge(merge_defaults(), %{block_categories: ["food"]})
      assert result.block_categories == ["food"]
      assert result.allow_categories == ["elixir", "erlang"]
    end

    test "per_feed strip_images overrides default" do
      result = Filters.merge(merge_defaults(), %{strip_images: true})
      assert result.strip_images == true
    end

    test "per_feed excerpt_length overrides default" do
      result = Filters.merge(merge_defaults(), %{excerpt_length: 200})
      assert result.excerpt_length == 200
    end

    test "per_feed nil values leave the default in place" do
      result =
        Filters.merge(merge_defaults(), %{
          strip_images: nil,
          excerpt_length: nil,
          allow_categories: nil,
          block_categories: nil
        })

      assert result == merge_defaults()
    end
  end

  describe "apply/2 — category filtering" do
    test "no filters: keeps all posts" do
      posts = [post(categories: ["elixir"]), post(categories: nil)]
      assert Filters.apply(posts, filters()) == posts
    end

    test "allow_categories: keeps posts with at least one matching category" do
      keep = post(categories: ["erlang", "otp"])
      drop = post(categories: ["food"])

      assert Filters.apply([keep, drop], filters(allow_categories: ["elixir", "erlang"])) ==
               [keep]
    end

    test "allow_categories: drops posts whose categories are nil" do
      assert Filters.apply([post(categories: nil)], filters(allow_categories: ["elixir"])) == []
    end

    test "allow_categories: comparison is case-insensitive" do
      assert Filters.apply([post(categories: ["elixir"])], filters(allow_categories: ["Elixir"])) ==
               [post(categories: ["elixir"])]
    end

    test "block_categories: drops posts with any matching category" do
      keep = post(categories: ["elixir"])
      drop = post(categories: ["elixir", "personal"])

      assert Filters.apply([keep, drop], filters(block_categories: ["personal"])) == [keep]
    end

    test "block_categories: posts with nil categories pass" do
      assert Filters.apply([post(categories: nil)], filters(block_categories: ["personal"])) ==
               [post(categories: nil)]
    end

    test "block_categories: comparison is case-insensitive" do
      assert Filters.apply(
               [post(categories: ["personal"])],
               filters(block_categories: ["Personal"])
             ) ==
               []
    end

    test "allow + block combined: post must match allow AND not match block" do
      keep = post(categories: ["elixir"])
      drop_no_match = post(categories: ["food"])
      drop_blocked = post(categories: ["elixir", "draft"])

      filters = filters(allow_categories: ["elixir"], block_categories: ["draft"])
      assert Filters.apply([keep, drop_no_match, drop_blocked], filters) == [keep]
    end
  end

  describe "apply/2 — strip_images" do
    test "replaces <img alt=\"X\" src=\"Y\"> with <a href=\"Y\">X</a> in body" do
      post = post(body: ~s(<p>before <img alt="cat" src="https://i.example/cat.png"> after</p>))

      [result] = Filters.apply([post], filters(strip_images: true))
      assert result.body =~ ~s(<a href="https://i.example/cat.png">cat</a>)
      refute result.body =~ "<img"
    end

    test "drops images that have no alt attribute" do
      post = post(body: ~s(<p>before<img src="https://i.example/cat.png">after</p>))

      [result] = Filters.apply([post], filters(strip_images: true))
      refute result.body =~ "<img"
      refute result.body =~ "<a href"
    end

    test "image with no src renders alt as plain text" do
      post = post(body: ~s(<p>before <img alt="logo"> after</p>))

      [result] = Filters.apply([post], filters(strip_images: true))
      refute result.body =~ "<img"
      refute result.body =~ "<a "
      assert result.body =~ "logo"
    end

    test "applies the same transformation to summary when present" do
      post = post(summary: ~s(<p><img alt="x" src="https://e/x.png"></p>))

      [result] = Filters.apply([post], filters(strip_images: true))
      assert result.summary =~ ~s(<a href="https://e/x.png">x</a>)
    end

    test "strip_images: false leaves images intact" do
      post = post(body: ~s(<p><img alt="x" src="https://e/x.png"></p>))

      [result] = Filters.apply([post], filters(strip_images: false))
      assert result.body =~ "<img"
    end

    test "leaves nil body and summary alone" do
      post = post(body: nil, summary: nil)

      [result] = Filters.apply([post], filters(strip_images: true))
      assert result.body == nil
      assert result.summary == nil
    end

    test "preserves image-free body byte-identical" do
      html = "<p>plain & simple <br> text</p>"
      post = post(body: html)

      [result] = Filters.apply([post], filters(strip_images: true))
      assert result.body == html
    end

    test "rewrites images nested inside other containers" do
      post = post(body: ~s(<div><figure><img alt="x" src="https://e/x.png"></figure></div>))

      [result] = Filters.apply([post], filters(strip_images: true))
      assert result.body =~ ~s(<a href="https://e/x.png">x</a>)
      refute result.body =~ "<img"
      assert result.body =~ "<figure"
      assert result.body =~ "<div"
    end
  end

  describe "apply/2 — excerpt_length" do
    test "summary already shorter than excerpt_length is left untouched" do
      post = post(body: "<p>full body</p>", summary: "short")
      [result] = Filters.apply([post], filters(excerpt_length: 30))
      assert result.summary == "short"
    end

    test "summary longer than excerpt_length is replaced with truncated text" do
      summary = "<p>" <> String.duplicate("word ", 50) <> "</p>"
      post = post(summary: summary)
      [result] = Filters.apply([post], filters(excerpt_length: 30))
      assert String.length(result.summary) <= 30
      assert String.ends_with?(result.summary, "…")
    end

    test "summary absent: a summary is generated from body" do
      body = "<p>" <> String.duplicate("hello ", 20) <> "</p>"
      post = post(body: body, summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 30))
      assert is_binary(result.summary)
      assert String.length(result.summary) <= 30
      assert String.ends_with?(result.summary, "…")
    end

    test "body is never modified by excerpt_length" do
      body = "<p>" <> String.duplicate("hello ", 20) <> "</p>"
      post = post(body: body, summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 30))
      assert result.body == body
    end

    test "excerpt_length: nil leaves summary unchanged" do
      summary = String.duplicate("word ", 50)
      post = post(summary: summary)
      [result] = Filters.apply([post], filters(excerpt_length: nil))
      assert result.summary == summary
    end

    test "truncation breaks at the last whitespace before the limit" do
      post = post(body: "<p>aaa bbb ccc ddd eee</p>", summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 10))
      assert String.length(result.summary) <= 10
      assert String.ends_with?(result.summary, "…")
      prefix = String.replace_trailing(result.summary, "…", "") |> String.trim_trailing()
      assert prefix == "" or Regex.match?(~r/^\w+( \w+)*$/, prefix)
    end

    test "truncates multi-byte UTF-8 content at correct grapheme boundary" do
      post = post(body: "<p>你好 abc def ghi</p>", summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 11))
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
      # Body with only an image and no text content — html_to_text yields "".
      post = post(body: ~s(<p><img src="https://e/x.png"></p>), summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 100))

      # nil (not "") so consumers using `summary || body` fall back to body.
      assert result.summary == nil
    end

    test "html-escapes the generated excerpt so consumers can render with raw/1" do
      body = ~s(<p>Code example: <pre>&lt;div class="x"&gt;hello&lt;/div&gt;</pre></p>)
      post = post(body: body, summary: nil)
      [result] = Filters.apply([post], filters(excerpt_length: 200))

      # `LazyHTML.text/1` decodes `&lt;` / `&gt;` back to `<` / `>` — those
      # would break the consumer's layout if not re-escaped before rendering.
      refute result.summary =~ "<div"
      refute result.summary =~ "</div>"
      assert result.summary =~ "&lt;div"
      assert result.summary =~ "&lt;/div&gt;"
    end
  end

  # Filter map with empty/false defaults; pass overrides as a keyword list or map.
  defp filters(overrides \\ []) do
    Map.merge(
      %{
        allow_categories: [],
        block_categories: [],
        strip_images: false,
        excerpt_length: nil
      },
      Map.new(overrides)
    )
  end

  # Placeholder Post struct; pass a keyword list of overrides to set fields.
  defp post(overrides) do
    defaults = %Exoplanet.Post{
      id: "1",
      feed_url: "https://example.com/feed",
      authors: ["Alice"],
      title: "T",
      body: "<p>body</p>",
      categories: nil,
      published: nil,
      summary: nil
    }

    struct!(defaults, overrides)
  end
end

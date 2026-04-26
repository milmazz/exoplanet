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
end

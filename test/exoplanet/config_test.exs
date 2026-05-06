defmodule Exoplanet.ConfigTest do
  use ExUnit.Case, async: true

  alias Exoplanet.Config

  describe "default_filters" do
    test "default value is an empty filter map" do
      config = struct!(Config, sources: %{})

      assert config.default_filters == %{
               allow_categories: [],
               block_categories: [],
               strip_images: false,
               excerpt_length: nil,
               sanitize_html: true,
               dropped_tags: ~w(iframe script object embed),
               dropped_attrs: ~w(style)
             }
    end

    @tag :tmp_dir
    test "from_file/1 loads default_filters when present in the config file", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.exs")

      File.write!(path, """
      %{
        sources: %{},
        default_filters: %{
          allow_categories: ["elixir"],
          block_categories: ["spam"],
          strip_images: true,
          excerpt_length: 500
        }
      }
      """)

      config = Config.from_file(path)

      assert config.default_filters == %{
               allow_categories: ["elixir"],
               block_categories: ["spam"],
               strip_images: true,
               excerpt_length: 500
             }
    end

    @tag :tmp_dir
    test "from_file/1 ignores unknown keys", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "config.exs")

      File.write!(path, """
      %{
        sources: %{},
        name: "ignored",
        owner_email: "ignored@example.com",
        related_sites: %{}
      }
      """)

      assert %Config{sources: %{}} = Config.from_file(path)
    end
  end
end

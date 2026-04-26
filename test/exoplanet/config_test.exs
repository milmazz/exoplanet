defmodule Exoplanet.ConfigTest do
  use ExUnit.Case, async: true

  alias Exoplanet.Config

  describe "default_filters" do
    test "default value is an empty filter map" do
      config =
        struct!(Config,
          name: "Test",
          link: "https://t.example",
          owner_name: "T",
          owner_email: "t@example.com",
          sources: %{},
          about: ""
        )

      assert config.default_filters == %{
               allow_categories: [],
               block_categories: [],
               strip_images: false,
               excerpt_length: nil
             }
    end

    test "from_file/1 loads default_filters when present in the config file" do
      path = Path.join(System.tmp_dir!(), "exoplanet_test_config.exs")

      File.write!(path, """
      %{
        name: "T",
        link: "https://t.example",
        owner_name: "T",
        owner_email: "t@example.com",
        sources: %{},
        about: "",
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

      File.rm!(path)
    end
  end
end

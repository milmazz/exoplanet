defmodule Exoplanet.Config do
  @moduledoc """
  Exoplanet configuration

  In this section we expect the following attributees:

  * `name` - your planet's name
  * `link` - link to the main page
  * `owner_name` - your name
  * `owner_email` - your e-mail address
  * `about` - information about your Planet
  * `feed_timeout` - time in seconds the request to any given feed should timeout
  * `related_sites` - map of links to related sites, like other Planets or Feed Aggregators
  """

  @type t :: %__MODULE__{
          name: String.t(),
          link: String.t(),
          owner_email: String.t(),
          owner_name: String.t(),
          about: String.t(),
          sources: map(),
          new_feed_items: pos_integer(),
          feed_timeout: pos_integer(),
          related_sites: map()
        }

  @enforce_keys [:name, :link, :owner_name, :owner_email, :sources, :about]
  defstruct [
    :name,
    :link,
    :owner_name,
    :owner_email,
    :sources,
    :cache_directory,
    :output_dir,
    :about,
    activity_threshold: 90,
    new_feed_items: 4,
    log_level: :debug,
    feed_timeout: 20,
    items: 60,
    output_theme: "classic_fancy",
    related_sites: %{}
  ]

  @doc """
  Creates `Exoplanet.Config` from the given file
  """
  @spec from_file(Path.t()) :: t()
  def from_file(path) when is_binary(path) do
    {attrs, _} =
      path
      |> File.read!()
      |> Code.eval_string()

    struct!(Exoplanet.Config, attrs)
  end
end

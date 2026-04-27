defmodule Exoplanet.Config do
  @moduledoc """
  Exoplanet configuration.

  Required keys:

  * `name` — your planet's name
  * `link` — link to the main page
  * `owner_name` — your name
  * `owner_email` — your e-mail address
  * `about` — information about your Planet (Markdown)
  * `sources` — map of `feed_url => %{name: ...}` (plus optional per-feed keys)

  Optional keys (with defaults):

  * `code_of_conduct` (`""`) — Markdown shown on a code-of-conduct page
  * `activity_threshold` (`90`) — days before a feed is considered inactive
  * `new_feed_items` (`4`) — max posts kept per feed per rebuild
  * `feed_timeout` (`20`) — per-feed HTTP timeout in seconds
  * `items` (`60`) — total post cap across all feeds
  * `related_sites` (`%{}`) — map of links to related sites
  * `default_filters` — global content filters (see `Exoplanet.Filters`)
  """

  @type t :: %__MODULE__{
          name: String.t(),
          link: String.t(),
          owner_email: String.t(),
          owner_name: String.t(),
          about: String.t(),
          code_of_conduct: String.t(),
          sources: map(),
          activity_threshold: pos_integer(),
          new_feed_items: pos_integer(),
          feed_timeout: pos_integer(),
          items: pos_integer(),
          related_sites: map(),
          default_filters: Exoplanet.Filters.t()
        }

  @enforce_keys [:name, :link, :owner_name, :owner_email, :sources, :about]
  defstruct [
    :name,
    :link,
    :owner_name,
    :owner_email,
    :sources,
    :about,
    code_of_conduct: "",
    activity_threshold: 90,
    new_feed_items: 4,
    feed_timeout: 20,
    items: 60,
    related_sites: %{},
    default_filters: %{
      allow_categories: [],
      block_categories: [],
      strip_images: false,
      excerpt_length: nil
    }
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

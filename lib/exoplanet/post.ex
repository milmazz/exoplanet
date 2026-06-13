defmodule Exoplanet.Post do
  @moduledoc """
  Post definition

  Exoplanet will produce a list of these feed entries.

  ## Time zones

  `published` and `updated` are `NaiveDateTime` values: the original UTC offset
  from the source feed is discarded (RSS dates are parsed by
  `Exoplanet.DateTimeParser`, Atom dates by `NaiveDateTime.from_iso8601/1`, and
  neither keeps the zone). The merged feed is sorted by `published` descending,
  treating each timestamp as wall-clock time, so posts from feeds in different
  zones can be ordered relative to each other with an error up to the offset
  difference (~24h). Normalise to UTC yourself if you need globally-correct
  chronological ordering.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          feed_url: String.t(),
          authors: [String.t()],
          title: String.t(),
          body: String.t() | nil,
          categories: [String.t()] | nil,
          published: NaiveDateTime.t() | nil,
          updated: NaiveDateTime.t() | nil,
          summary: String.t() | nil
        }
  @enforce_keys [:id, :feed_url, :authors, :title, :body, :published]
  defstruct [:id, :feed_url, :authors, :title, :body, :categories, :published, :updated, :summary]

  @doc """
  Builds the struct of posts or feed entries
  """
  @spec build(map(), String.t() | nil) :: t()
  def build(attrs, body) do
    attrs =
      Map.take(attrs, [
        :id,
        :feed_url,
        :authors,
        :title,
        :categories,
        :published,
        :updated,
        :summary
      ])

    struct!(__MODULE__, [body: body] ++ Map.to_list(attrs))
  end
end

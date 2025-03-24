defmodule Exoplanet.Config do
  @enforce_keys [:name, :link, :owner_name, :owner_email, :sources]
  defstruct [
    :name,
    :link,
    :owner_name,
    :owner_email,
    :sources,
    :cache_directory,
    :output_dir,
    activity_threshold: 90,
    new_feed_items: 4,
    log_level: :debug,
    feed_timeout: 20,
    items_per_page: 60,
    output_theme: "classic_fancy"
  ]

  @doc """
  Creates `Exoplanet.Config` from the given File
  """
  def from_file(path) when is_binary(path) do
    {attrs, _} =
      path
      |> File.read!()
      |> Code.eval_string()

    struct!(Exoplanet.Config, attrs)
  end
end

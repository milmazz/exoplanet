defmodule Exoplanet.Post do
  @enforce_keys [:id, :authors, :title, :body, :published]
  defstruct [:id, :authors, :title, :body, :published]

  def build(attrs, body) do
    attrs = Map.take(attrs, [:id, :authors, :title, :published])

    struct!(__MODULE__, [body: body] ++ Map.to_list(attrs))
  end
end

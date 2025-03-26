defmodule Exoplanet.Post do
  @moduledoc """
  Post definition

  Exoplanet will produce a list of these feed entries
  """

  @type t :: %__MODULE__{
          id: String.t(),
          authors: [String.t()],
          title: String.t(),
          body: String.t(),
          published: NaiveDateTime.t()
        }
  @enforce_keys [:id, :authors, :title, :body, :published]
  defstruct [:id, :authors, :title, :body, :published]

  @doc """
  Builds the struct of posts or feed entries
  """
  @spec build(map(), String.t()) :: t()
  def build(attrs, body) do
    attrs = Map.take(attrs, [:id, :authors, :title, :published])

    struct!(__MODULE__, [body: body] ++ Map.to_list(attrs))
  end
end

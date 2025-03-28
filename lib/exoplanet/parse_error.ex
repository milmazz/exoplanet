defmodule Exoplanet.ParseError do
  @moduledoc """
  Used for errors found during parsing
  """
  defexception message: "Invalid input!"

  def exception(message: message) do
    %__MODULE__{message: message}
  end
end

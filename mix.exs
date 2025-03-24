defmodule Exoplanet.MixProject do
  use Mix.Project

  def project do
    [
      app: :exoplanet,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:fast_rss, "~> 0.5"},
      {:timex, "~> 3.7"},
      {:plug, "~> 1.0", only: [:test]}
    ]
  end
end

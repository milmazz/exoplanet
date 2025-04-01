defmodule Exoplanet.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :exoplanet,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # Docs
      name: "Exoplanet",
      source_url: "https://github.com/milmazz/exoplanet",
      docs: &docs/0,
      # Package
      package: package(),
      description:
        "Exoplanet is a feed aggregator library that combines multiple RSS and Atom sources into a single, unified feed."
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
      {:nimble_parsec, "~> 1.0", only: [:dev], runtime: false},
      {:plug, "~> 1.0", only: [:test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "Exoplanet",
      extras: ["README.md"]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/milmazz/exoplanet"}
    ]
  end
end

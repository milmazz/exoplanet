defmodule Exoplanet.MixProject do
  use Mix.Project

  @version "0.6.1-dev"

  def project do
    [
      app: :exoplanet,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:fast_rss, "~> 0.5"},
      {:lazy_html, "~> 0.1"},
      {:nimble_parsec, "~> 1.0", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.0", only: [:test]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"],
      # Private modules referenced from the changelog and contributing guide.
      skip_code_autolink_to: [
        "Exoplanet.Fetcher",
        "Exoplanet.Parser",
        "Exoplanet.DateTimeParser",
        "Exoplanet.DateTimeParser.parse/1"
      ]
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "docs --warnings-as-errors",
        "test"
      ]
    ]
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Milton Mazzarri"],
      files: ~w(lib example mix.exs README.md CHANGELOG.md CONTRIBUTING.md LICENSE),
      links: %{"GitHub" => "https://github.com/milmazz/exoplanet"}
    ]
  end
end

defmodule Exoplanet.AtomPostIdTest do
  # Regression coverage for QA-1: Atom <id> can legally be a non-URL IRI
  # (RFC 4287 §4.2.6) — Bridgetown emits `repo://...md`. The post id used
  # downstream must be a usable HTTP/HTTPS URL drawn from
  # `<link rel="alternate">`, falling back to `<id>` only when no usable
  # link is present.
  use ExUnit.Case, async: true

  import Exoplanet.TestHelpers

  test "prefers <link rel=\"alternate\"> over a non-URL Atom <id>" do
    stub_feed(:atom_bridgetown_urn_id)

    sources = %{"https://katafrakt.me/feed.xml" => %{name: "katafrakt"}}
    [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

    assert post.id == "https://katafrakt.me/2026/01/03/elixir-head-with-mise/"
    refute post.id =~ "repo://"
  end

  test "falls back to <id> when no usable <link> is present (only rel=self)" do
    stub_feed(:atom_no_alternate_link)

    sources = %{"https://only-self.example/feed.xml" => %{name: "x"}}
    [%Exoplanet.Post{} = post] = Exoplanet.build(build_config(sources: sources))

    # No <link rel="alternate"> exists, so we keep <id> as the post id.
    assert post.id == "https://only-self.example/canonical/post-1"
  end

  defp build_config(opts), do: struct!(Exoplanet.Config, opts)
end

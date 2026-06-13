defmodule Exoplanet.ReqOptionsTest do
  # async: false — swaps global application env keys.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Exoplanet.TestHelpers

  test "deprecated :planet_req_options key still works as a fallback" do
    opts = Application.fetch_env!(:exoplanet, :req_options)
    Application.delete_env(:exoplanet, :req_options)
    Application.put_env(:exoplanet, :planet_req_options, opts)

    on_exit(fn ->
      Application.delete_env(:exoplanet, :planet_req_options)
      Application.put_env(:exoplanet, :req_options, opts)
      :persistent_term.erase({Exoplanet.Fetcher, :legacy_req_options_warned})
    end)

    stub_feed(:atom)
    sources = %{"https://milmazz.uno/atom.xml" => %{name: "Milton Mazzarri"}}

    # If the fallback broke, the Req.Test plug stub would not be picked up and
    # the request would fail (no real network in tests).
    {[post], log} =
      with_log(fn ->
        Exoplanet.build(struct!(Exoplanet.Config, sources: sources))
      end)

    assert post.title == "Oban: Testing your Workers and Configuration"
    assert log =~ ":planet_req_options application env key is deprecated"
  end
end

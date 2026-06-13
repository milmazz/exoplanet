Application.put_env(:exoplanet, :req_options,
  plug: {Req.Test, Exoplanet.Fetcher},
  retry: false
)

ExUnit.start()

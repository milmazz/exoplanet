Application.put_env(:exoplanet, :planet_req_options,
  plug: {Req.Test, Exoplanet.Parser},
  retry: false
)

ExUnit.start()

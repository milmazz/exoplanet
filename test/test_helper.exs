Application.put_env(:exoplanet, :req_options,
  plug: {Req.Test, Exoplanet.Parser},
  retry: false
)

ExUnit.start()

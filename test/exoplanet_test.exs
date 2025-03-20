defmodule ExoplanetTest do
  use ExUnit.Case
  doctest Exoplanet

  test "greets the world" do
    assert Exoplanet.hello() == :world
  end
end

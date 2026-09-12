defmodule AshR2RML.WS5.CryptoRuntimeContractTest do
  use ExUnit.Case, async: true

  test "crypto remains an explicit runtime application" do
    source = File.read!("mix.exs")
    assert Regex.match?(~r/extra_applications:\s*\[[^\]]*:crypto/, source)
  end
end

defmodule AshR2RML.WS5.SobelowAliasContractTest do
  use ExUnit.Case, async: true

  test "Sobelow remains explicitly available through the repository alias" do
    source = File.read!("mix.exs")
    assert source =~ ~s(sobelow: "sobelow --skip")
  end
end

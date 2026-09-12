defmodule AshR2RML.WS5.ElixirFloorContractTest do
  use ExUnit.Case, async: true

  test "Elixir compatibility floor remains 1.17" do
    source = File.read!("mix.exs")
    assert source =~ ~s(elixir: "~> 1.17")
  end
end

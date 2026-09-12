defmodule AshR2RML.WS5.ProtocolConsolidationContractTest do
  use ExUnit.Case, async: true

  test "protocol consolidation remains production-only" do
    source = File.read!("mix.exs")
    assert source =~ "consolidate_protocols: Mix.env() == :prod"
  end
end

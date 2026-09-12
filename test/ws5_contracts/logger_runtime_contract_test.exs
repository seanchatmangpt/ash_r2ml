defmodule AshR2RML.WS5.LoggerRuntimeContractTest do
  use ExUnit.Case, async: true

  test "logger remains an explicit runtime application" do
    source = File.read!("mix.exs")
    assert source =~ "extra_applications: [:logger, :crypto]"
  end
end

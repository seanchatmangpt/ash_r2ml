defmodule AshR2RML.WS5.TestSupportCompilePathTest do
  use ExUnit.Case, async: true

  test "test environment compiles support modules" do
    source = File.read!("mix.exs")
    assert source =~ ~s|defp elixirc_paths(:test), do: ["lib", "test/support"]|
  end
end

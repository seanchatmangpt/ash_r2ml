defmodule AshR2RML.WS5.PackageVersionContractTest do
  use ExUnit.Case, async: true

  test "package version remains the admitted 26.8.25 line" do
    source = File.read!("mix.exs")
    assert source =~ ~s(@version "26.8.25")
  end
end

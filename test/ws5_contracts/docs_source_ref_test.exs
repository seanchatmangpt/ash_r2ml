defmodule AshR2RML.WS5.DocsSourceRefTest do
  use ExUnit.Case, async: true

  test "documentation source ref remains version-bound" do
    source = File.read!("mix.exs")
    assert source =~ ~s(source_ref: "v\#{@version}")
  end
end

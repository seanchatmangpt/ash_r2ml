defmodule AshR2RML.WS5.SparkFormatterExtensionTest do
  use ExUnit.Case, async: true

  test "Spark formatter remains bound to AshR2RML.Resource" do
    source = File.read!("mix.exs")
    assert source =~ ~s("spark.formatter": "spark.formatter --extensions AshR2RML.Resource")
  end
end

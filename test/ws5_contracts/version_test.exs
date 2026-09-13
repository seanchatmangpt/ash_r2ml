defmodule AshR2RML.WS5.VersionContractTest do
  use ExUnit.Case, async: true
  @manifest File.read!("mix.exs")

  # Stale hardcoded literal, not a compatibility pin (recurred twice: e41ec3c bumped
  # 26.8.25->26.8.26 for the same reason; mix.exs later moved 26.8.29 -> 26.9.12).
  # Assert dynamically against Mix.Project config so this can't go stale again.
  test "package version manifest matches Mix.Project config" do
    version = Mix.Project.config()[:version]
    assert @manifest =~ ~s(@version "#{version}")
  end
end

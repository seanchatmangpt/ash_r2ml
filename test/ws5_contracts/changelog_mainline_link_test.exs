defmodule AshR2RML.WS5.ChangelogMainlineLinkTest do
  use ExUnit.Case, async: true

  test "package changelog link resolves through main" do
    source = File.read!("mix.exs")
    assert source =~ ~s("Changelog" => "\#{@github_url}/blob/main/CHANGELOG.md")
  end
end

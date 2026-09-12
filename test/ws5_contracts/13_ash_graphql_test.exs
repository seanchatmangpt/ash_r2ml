defmodule AshR2RML.WS5.AshGraphqlTest do
  use ExUnit.Case, async: true

  # Updated when `AshR2RML.Graphql` (the query-only GraphQL projection) landed:
  # ash_graphql moved from `only: [:test]` to a normal optional dependency so the
  # projection is compilable and usable by consumers in :dev/:prod. It remains an
  # explicit, opt-in projection integration -- every projection module is guarded
  # by `Code.ensure_loaded?(AshGraphql.Resource)`.
  test "AshGraphql remains an explicit projection integration" do
    mix_exs = File.read!("mix.exs")

    assert mix_exs =~ ~s({:ash_graphql, "~> 1.10", optional: true})
    assert mix_exs =~ ~s({:absinthe, "~> 1.7", optional: true})

    assert File.read!("lib/ash_r2rml/graphql.ex") =~
             "Code.ensure_loaded?(AshGraphql.Resource)"
  end
end

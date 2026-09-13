# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GraphqlShortNameCollisionTest do
  @moduledoc """
  Real falsifier for the shared `AshR2RML.Graphql.Transformers.DeriveQueries`
  short-name path (`derive_type/1`, which delegates to
  `Ash.Resource.Info.short_name/1`).

  Fixtures: `test/support/graphql_short_name_collision/resources.ex` declares
  two resources, `AshR2RML.ShortNameCollision.NsA.Widget` and
  `...NsB.Widget`, in different namespaces. Neither sets `resource short_name:
  ...`, so both fall back to `default_short_name/0` (last module segment,
  underscored) and both derive the identical `:widget` GraphQL type and the
  identical `:widget`/`:widgets` query names -- a real, reachable collision:
  nothing in `AshR2RML.Graphql` or `AshR2RML.Resource.Info` requires resource
  authors to set an explicit unique short name.

  Per-resource, `derive_queries/1` runs deterministically and collision-free
  (each resource sees only its own actions) -- the moduledoc's "collision-free
  by construction" claim holds *per resource*. It does NOT hold *across* two
  resources sharing a default short name in the same schema: this is the real,
  observed current behavior, established by actually building an
  `AshR2RML.Graphql.Schema` over a domain containing both and letting Absinthe
  compile it, per `superpowers:test-driven-development` Chicago-style
  discipline (no mocked schema compiler).
  """
  use ExUnit.Case, async: false

  alias AshR2RML.ShortNameCollision.NsA
  alias AshR2RML.ShortNameCollision.NsB

  describe "both resources independently derive the same short name" do
    test "Ash.Resource.Info.short_name/1 resolves to :widget for both, with no explicit override" do
      assert Ash.Resource.Info.short_name(NsA.Widget) == :widget
      assert Ash.Resource.Info.short_name(NsB.Widget) == :widget
    end

    test "AshGraphql.Resource.Info.type/1 (set by derive_type/1) is identical for both" do
      assert AshGraphql.Resource.Info.type(NsA.Widget) == :widget
      assert AshGraphql.Resource.Info.type(NsB.Widget) == :widget
    end

    test "each resource's own derived queries are internally collision-free and identically named across resources" do
      # Per-resource this is exactly the moduledoc's claim: deterministic,
      # sorted-by-name, collision-free query derivation.
      assert Enum.map(AshR2RML.Graphql.Info.derived_queries(NsA.Widget), &{&1.name, &1.type, &1.action}) ==
               [{:widget, :get, :read}, {:widgets, :list, :read}]

      assert Enum.map(AshR2RML.Graphql.Info.derived_queries(NsB.Widget), &{&1.name, &1.type, &1.action}) ==
               [{:widget, :get, :read}, {:widgets, :list, :read}]
    end
  end

  describe "the collision is caught, not silently producing a broken schema" do
    test "compiling one Absinthe schema over both resources raises a real Absinthe.Schema.Error naming the duplicate fields" do
      # Real schema compilation (this module's `use AshR2RML.Graphql.Schema`
      # expansion triggers Absinthe's `@after_compile` validation) -- not a
      # mocked or stubbed compiler. The collision is refused loudly at compile
      # time, never silently accepted into a broken runtime schema.
      assert_raise Absinthe.Schema.Error, ~r/widgets?.*not unique|not unique.*widgets?/is, fn ->
        Code.compile_string("""
        defmodule AshR2RML.ShortNameCollisionTest.CollidingSchema do
          use AshR2RML.Graphql.Schema, domains: [AshR2RML.ShortNameCollision.Domain]
        end
        """)
      end
    end
  end
end

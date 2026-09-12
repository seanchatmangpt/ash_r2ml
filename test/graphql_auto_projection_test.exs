# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GraphqlAutoProjectionTest do
  @moduledoc """
  Real falsifiers for the ZERO-CONSUMER-SURFACE projection: the fixtures in
  `test/support/graphql_auto_projection/resources.ex` declare only `AshR2RML` /
  `AshR2RML.Resource` and never name `AshR2RML.Graphql` or
  `AshGraphql.Resource`. Every assertion below therefore tests the implicit
  `add_extensions:` path, not the explicit one.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GraphqlAutoProjection.Drone
  alias AshR2RML.GraphqlAutoProjection.Robot
  alias AshR2RML.GraphqlAutoProjection.Schema

  setup do
    for resource <- [Robot, Drone] do
      resource |> Ash.read!() |> Enum.each(&Ash.destroy!/1)
    end

    :ok
  end

  describe "the fixtures really do not declare the GraphQL extensions" do
    test "neither resource declares a GraphQL extension or a graphql block in its source" do
      source = File.read!(Path.join(__DIR__, "support/graphql_auto_projection/resources.ex"))

      # Every `extensions:` list in the fixture file, verbatim.
      extension_lists = Regex.scan(~r/extensions: \[[^\]]*\]/, source) |> List.flatten()

      assert Enum.sort(Enum.uniq(extension_lists)) ==
               ["extensions: [AshR2RML.Resource]", "extensions: [AshR2RML]"]

      # No resource body writes a `graphql do ... end` or `r2rml_graphql do ... end`
      # block: the projection is configured by nothing at all.
      refute source =~ ~r/^\s*graphql do/m
      refute source =~ ~r/^\s*r2rml_graphql do/m
    end

    test "Robot declares exactly [AshR2RML.Resource], Drone exactly [AshR2RML]" do
      # `Spark.extensions/1` returns the post-expansion set, so the implicitly
      # added extensions must appear there while the source above names none.
      robot = Spark.extensions(Robot)
      drone = Spark.extensions(Drone)

      assert AshR2RML.Resource in robot
      assert AshR2RML.Graphql in robot
      assert AshGraphql.Resource in robot

      assert AshR2RML in drone
      assert AshR2RML.Graphql in drone
      assert AshGraphql.Resource in drone
    end
  end

  describe "derived queries" do
    test "both resources get get/list queries over the public read action only" do
      assert Enum.map(AshR2RML.Graphql.Info.derived_queries(Robot), &{&1.name, &1.type, &1.action}) ==
               [{:robot, :get, :read}, {:robots, :list, :read}]

      assert Enum.map(AshR2RML.Graphql.Info.derived_queries(Drone), &{&1.name, &1.type, &1.action}) ==
               [{:drone, :get, :read}, {:drones, :list, :read}]
    end

    test "no derived query is a mutation" do
      for resource <- [Robot, Drone] do
        assert Enum.all?(AshR2RML.Graphql.Info.derived_queries(resource), &(&1.as_mutation? == false))
      end
    end

    test "the GraphQL type name is auto-derived from the module's short name" do
      assert AshGraphql.Resource.Info.type(Robot) == :robot
      assert AshGraphql.Resource.Info.type(Drone) == :drone
    end
  end

  describe "real Absinthe execution" do
    test "list query returns real ETS-stored rows for the AshR2RML.Resource fixture" do
      Ash.create!(Ash.Changeset.for_create(Robot, :create, %{name: "R2"}))
      Ash.create!(Ash.Changeset.for_create(Robot, :create, %{name: "C3"}))

      assert {:ok, %{data: %{"robots" => %{"results" => robots}}}} =
               Absinthe.run("{ robots { results { id name } } }", Schema)

      assert robots |> Enum.map(& &1["name"]) |> Enum.sort() == ["C3", "R2"]
      assert Enum.all?(robots, &is_binary(&1["id"]))
    end

    test "get query returns the real row by primary key" do
      robot = Ash.create!(Ash.Changeset.for_create(Robot, :create, %{name: "R2"}))

      assert {:ok, %{data: %{"robot" => %{"id" => id, "name" => "R2"}}}} =
               Absinthe.run(~s|{ robot(id: "#{robot.id}") { id name } }|, Schema)

      assert id == robot.id
    end

    test "list query returns real rows for the AshR2RML fixture too" do
      Ash.create!(Ash.Changeset.for_create(Drone, :create, %{name: "Skydio"}))

      assert {:ok, %{data: %{"drones" => %{"results" => [%{"name" => "Skydio"}]}}}} =
               Absinthe.run("{ drones { results { id name } } }", Schema)
    end

    test "the in-band schema sha field resolves" do
      assert {:ok, %{data: %{"r2rmlSchemaSha" => sha}}} = Absinthe.run("{ r2rmlSchemaSha }", Schema)
      assert sha == AshR2RML.Graphql.Schema.schema_sha(Schema)
    end
  end

  describe "query-only: no mutation or subscription surface" do
    test "no mutation root type exists despite create/update/destroy actions" do
      assert Absinthe.Schema.lookup_type(Schema, :mutation) == nil
      assert Absinthe.Schema.lookup_type(Schema, :root_mutation_type) == nil
      refute :mutation in Schema.__absinthe_types__()
      refute String.contains?(AshR2RML.Graphql.Schema.sdl(Schema), "RootMutationType")
    end

    test "a mutation document is rejected by the real schema" do
      assert {:ok, %{errors: errors}} =
               Absinthe.run(~s|mutation { createRobot(input: {name: "x"}) { id } }|, Schema)

      refute errors == []
    end

    test "subscription root is absent" do
      assert Absinthe.Schema.lookup_type(Schema, :subscription) == nil
    end

    test "the projection receipt reports both resources and no mutation root" do
      receipt = AshR2RML.Graphql.receipt(Schema)

      assert Enum.sort(receipt.resources) == Enum.sort([Robot, Drone])
      assert receipt.mutation_root == nil
      assert receipt.subscription_root == nil

      assert Enum.sort(Enum.map(receipt.queries, & &1.name)) == [:drone, :drones, :robot, :robots]
    end
  end

  describe "opt-out is still reachable without the explicit extension" do
    test "r2rml_graphql enabled? false suppresses the projection" do
      defmodule OptedOut do
        @moduledoc false
        use Ash.Resource,
          domain: nil,
          data_layer: Ash.DataLayer.Ets,
          extensions: [AshR2RML.Resource]

        r2rml do
          table_name("graphql_auto_projection_opted_out")
          class("https://example.org/ns#OptedOut")

          subject do
            template("https://example.org/opted-out/{id}")
          end

          property(:name, "https://example.org/ns#name")
        end

        r2rml_graphql do
          enabled?(false)
        end

        attributes do
          uuid_primary_key :id
          attribute :name, :string, allow_nil?: false, public?: true
        end

        actions do
          defaults [:read, create: [:name]]
        end
      end

      refute AshR2RML.Graphql.Info.enabled?(OptedOut)
      assert AshR2RML.Graphql.Info.derived_queries(OptedOut) == []
    end
  end
end

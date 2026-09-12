# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GraphqlQueryOnlyProjectionTest do
  @moduledoc """
  Real falsifiers for the `AshR2RML.Graphql` query-only projection: a real
  `Absinthe.run/2` execution against real ETS-stored rows, a real Absinthe
  introspection assertion that no mutation root exists, and a determinism
  assertion on `schema_sha/1`.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.GraphqlProjection.Person
  alias AshR2RML.GraphqlProjection.Schema

  setup do
    Person
    |> Ash.read!()
    |> Enum.each(&Ash.destroy!/1)

    :ok
  end

  test "derived queries are get/list over the public read action, nothing else" do
    queries = AshR2RML.Graphql.Info.derived_queries(Person)

    assert Enum.map(queries, &{&1.name, &1.type, &1.action}) == [
             {:person, :get, :read},
             {:persons, :list, :read}
           ]

    assert Enum.all?(queries, &(&1.as_mutation? == false))
  end

  test "real Absinthe.run/2 returns real stored data through the list query" do
    Ash.create!(Ash.Changeset.for_create(Person, :create, %{name: "Ada"}))
    Ash.create!(Ash.Changeset.for_create(Person, :create, %{name: "Grace"}))

    assert {:ok, %{data: %{"persons" => %{"results" => people}}}} =
             Absinthe.run("{ persons { results { id name } } }", Schema)

    assert Enum.map(people, & &1["name"]) |> Enum.sort() == ["Ada", "Grace"]
    assert Enum.all?(people, &is_binary(&1["id"]))
  end

  test "real Absinthe.run/2 returns the in-band schema sha field" do
    assert {:ok, %{data: %{"r2rmlSchemaSha" => sha}}} =
             Absinthe.run("{ r2rmlSchemaSha }", Schema)

    assert sha == AshR2RML.Graphql.Schema.schema_sha(Schema)
  end

  test "create/update actions produce no mutation field and no mutation root type" do
    assert Absinthe.Schema.lookup_type(Schema, :mutation) == nil
    assert Absinthe.Schema.lookup_type(Schema, :root_mutation_type) == nil
    refute :mutation in Schema.__absinthe_types__()
    refute String.contains?(AshR2RML.Graphql.Schema.sdl(Schema), "RootMutationType")

    assert {:ok, %{errors: errors}} =
             Absinthe.run("mutation { createPerson(input: {name: \"x\"}) { id } }", Schema)

    refute errors == []
  end

  test "subscription root is absent too" do
    assert Absinthe.Schema.lookup_type(Schema, :subscription) == nil
  end

  test "schema_sha/1 is deterministic across independent calls" do
    assert AshR2RML.Graphql.Schema.schema_sha(Schema) ==
             AshR2RML.Graphql.Schema.schema_sha(Schema)

    assert AshR2RML.Graphql.Schema.canonical_sdl(Schema) ==
             AshR2RML.Graphql.Schema.canonical_sdl(Schema)
  end

  test "golden sha falsifier" do
    path = Path.join(__DIR__, "support/graphql_projection/schema_sha.txt")
    sha = AshR2RML.Graphql.Schema.schema_sha(Schema)

    if File.exists?(path) do
      assert String.trim(File.read!(path)) == sha
    else
      File.write!(path, sha <> "\n")
      flunk("wrote golden sha #{sha}; re-run to assert against it")
    end
  end

  test "receipt/1 reports a query-only projection" do
    receipt = AshR2RML.Graphql.receipt(Schema)

    assert receipt.schema == Schema
    assert receipt.resources == [Person]
    assert receipt.mutation_root == nil
    assert receipt.subscription_root == nil
    assert receipt.sdl_bytes > 0
    assert receipt.sha256 == AshR2RML.Graphql.Schema.schema_sha(Schema)

    assert Enum.sort(Enum.map(receipt.queries, & &1.name)) == [:person, :persons]
  end

  test "declaring a mutation on a projected resource is refused at compile time" do
    source = """
    defmodule AshR2RML.GraphqlProjection.RefusedPerson do
      use Ash.Resource,
        data_layer: Ash.DataLayer.Ets,
        extensions: [AshR2RML, AshR2RML.Graphql]

      r2rml do
        class_iri("http://xmlns.com/foaf/0.1/Person")
        subject_template("https://example.org/refused/{id}")
        table_name("graphql_projection_refused")
        attribute_mappings([{:name, "http://xmlns.com/foaf/0.1/name"}])
      end

      attributes do
        uuid_primary_key :id
        attribute :name, :string, allow_nil?: false, public?: true
      end

      actions do
        defaults [:read, create: [:name]]
      end

      graphql do
        mutations do
          create :create_person, :create
        end
      end
    end
    """

    captured =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string(source)
      end)

    assert captured =~ "Spark.Error.DslError"
    assert captured =~ "graphql -> mutations"
    assert captured =~ "read-only projection"
  end

  test "zero-surface: the extension exposes exactly one option and no entities" do
    section = AshR2RML.Graphql.sections() |> hd()

    assert length(section.schema) == 1
    assert Keyword.keys(section.schema) == [:enabled?]
    assert section.entities == []
  end

  test "no mutation construction path exists in lib/ash_r2rml/graphql" do
    {out, status} =
      System.cmd(
        "grep",
        [
          "-rn",
          "--exclude=no_mutations.ex",
          "Resource.Mutation\\|:mutations\\|as_mutation?: true",
          "lib/ash_r2rml/graphql"
        ],
        stderr_to_stdout: true,
        cd: Path.expand("..", __DIR__)
      )

    assert out == ""
    assert status == 1
  end
end

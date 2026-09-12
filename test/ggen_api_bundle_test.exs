# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GgenApiBundleTest do
  @moduledoc """
  Verifies the API-adjacent ggen bundle keeps GraphQL a deterministic semantic
  projection rather than an AshGraphql configuration surface.

  The GraphQL path is deliberately read-only: `graphql: true` emits canonical
  SDL/manifest/receipt artifacts from the admitted `SemanticIR`, while the
  generated Ash resource receives no `AshGraphql.Resource` extension and no
  GraphQL DSL block. Custom GraphQL belongs in `ash_graphql`.
  """
  use ExUnit.Case, async: false

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile(module_name) do
    %{
      ontology_hash: "ontology:sha256:api-bundle",
      profile_hash: "profile:sha256:api-bundle",
      shacl_hash: "shacl:sha256:api-bundle",
      resources: [
        %{
          iri: "https://api-bundle.example/resource/Widget",
          class_iri: "https://api-bundle.example/ontology/Widget",
          shape_iri: "https://api-bundle.example/shapes/WidgetShape",
          module: module_name,
          table: "widgets",
          subject_template: "https://api-bundle.example/id/widget/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://api-bundle.example/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :name,
              predicate_iri: "http://xmlns.com/foaf/0.1/name",
              datatype_iri: @xsd_string,
              min_count: 1,
              max_count: 1
            }
          ],
          actions: [%{name: :rename_widget, kind: :update}]
        }
      ]
    }
  end

  test "with graphql: false, json_api: false (default), no external protocol extensions are added" do
    assert {:ok, bundle} = AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.PlainWidget"))
    source = bundle.files["generated/ash/api_resources.ex"]

    assert is_binary(source)
    refute source =~ "AshGraphql.Resource"
    refute source =~ "AshJsonApi.Resource"
    refute source =~ "graphql do"
    refute source =~ "json_api do"
    refute Map.has_key?(bundle.files, "generated/graphql/schema.graphql")
  end

  test "graphql: true emits canonical read-only SDL directly from SemanticIR without AshGraphql" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.GraphqlWidget"), graphql: true)

    source = bundle.files["generated/ash/api_resources.ex"]
    schema = bundle.files["generated/graphql/schema.graphql"]
    manifest = Jason.decode!(bundle.files["generated/graphql/semantic-manifest.json"])
    receipt = Jason.decode!(bundle.files["receipts/graphql-projection.json"])

    refute source =~ "AshGraphql.Resource"
    refute source =~ "graphql do"
    assert schema =~ "type Widget {"
    assert schema =~ "iri: ID!"
    assert schema =~ "id: ID!"
    assert schema =~ "name: String!"
    assert schema =~ "type Query {"
    assert schema =~ "widget(iri: ID!): Widget"
    assert schema =~ "widget_list(limit: Int = 100, offset: Int = 0): [Widget!]!"
    refute schema =~ "Mutation"
    refute schema =~ "Subscription"
    refute schema =~ "rename_widget"

    assert manifest["mode"] == "read_only"
    assert manifest["mutation_root"] == false
    assert manifest["customization"] == "unsupported_use_ash_graphql"
    assert manifest["consequence_path"] == "brce"
    assert receipt["standing"] == "constructed_read_only_schema"
    assert receipt["authority"] == "none"
    assert receipt["mutation_root"] == false
  end

  test "graphql accepts only a boolean switch and refuses customization" do
    assert {:error, %AshR2RML.Refusal{} = refusal} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.CustomGraphqlWidget"),
               graphql: [type: :custom_widget]
             )

    assert inspect(refusal) =~ "REFUSED_GRAPHQL_CUSTOMIZATION"
    assert inspect(refusal) =~ "ash_graphql"
  end

  test "main compile bundle and API bundle manufacture the same GraphQL schema from the same O*" do
    profile = profile("AshR2RML.ApiBundleTest.ReplayWidget")

    assert {:ok, full_bundle} = AshR2RML.Ggen.compile_bundle(profile, graphql: true)
    assert {:ok, api_bundle} = AshR2RML.Ggen.compile_api_bundle(profile, graphql: true)

    assert full_bundle.files["generated/graphql/schema.graphql"] ==
             api_bundle.files["generated/graphql/schema.graphql"]

    assert full_bundle.files["receipts/graphql-projection.json"] ==
             api_bundle.files["receipts/graphql-projection.json"]
  end

  test "json_api: true retains the pre-existing AshJsonApi projection independently" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.JsonApiWidget"), json_api: true)

    source = bundle.files["generated/ash/api_resources.ex"]
    assert source =~ "AshJsonApi.Resource"
    assert source =~ "json_api do"
    refute source =~ "AshGraphql.Resource"

    {_result, _bindings} = Code.eval_string(source)

    assert AshJsonApi.Resource in Spark.extensions(AshR2RML.ApiBundleTest.JsonApiWidget)
    assert AshJsonApi.Resource.Info.type(AshR2RML.ApiBundleTest.JsonApiWidget) == "json_api_widget"
  end

  test "GraphQL read projection composes with custom JSON:API without granting GraphQL writes" do
    assert {:ok, bundle} =
             AshR2RML.Ggen.compile_api_bundle(profile("AshR2RML.ApiBundleTest.BothWidget"),
               graphql: true,
               json_api: true
             )

    source = bundle.files["generated/ash/api_resources.ex"]
    schema = bundle.files["generated/graphql/schema.graphql"]
    {_result, _bindings} = Code.eval_string(source)

    extensions = Spark.extensions(AshR2RML.ApiBundleTest.BothWidget)
    assert AshR2RML in extensions
    assert AshJsonApi.Resource in extensions
    refute AshGraphql.Resource in extensions
    refute schema =~ "Mutation"

    assert AshR2RML.Resource.Info.mapped?(AshR2RML.ApiBundleTest.BothWidget)
    {:ok, mapping} = AshR2RML.mapping_result(AshR2RML.ApiBundleTest.BothWidget)
    assert mapping.class_iris == ["https://api-bundle.example/ontology/Widget"]
  end
end

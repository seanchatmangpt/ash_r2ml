# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticGraphQLDfCMTest do
  use ExUnit.Case, async: true

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp resource(name, module, table) do
    local = to_string(name)

    %{
      iri: "https://migration.example/resource/#{local}",
      class_iri: "https://migration.example/ontology/#{local}",
      shape_iri: "https://migration.example/shapes/#{local}Shape",
      module: module,
      table: table,
      subject_template: "https://migration.example/id/#{String.downcase(local)}/{id}",
      identities: [%{name: :primary, keys: [:id], primary?: true}],
      attributes: [
        %{
          name: :id,
          column: "id",
          predicate_iri: "https://migration.example/ontology/id",
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
          column: "name",
          predicate_iri: "http://xmlns.com/foaf/0.1/name",
          datatype_iri: @xsd_string,
          ash_type: :string,
          postgres_type: "TEXT",
          min_count: 1,
          max_count: 1,
          nullable: false
        }
      ],
      relationships: [],
      actions: [%{name: :rename, kind: :update}],
      policies: [
        %{
          name: :viewer_scope,
          effect: :permit,
          odrl_iri: "https://migration.example/policy/viewer-scope"
        }
      ]
    }
  end

  test "DfCM preserves read, policy, and consequence dimensions without selecting DO or storage" do
    owner = resource(:Owner, "AshR2RML.SemanticGraphQLDfCMTest.Owner", "owners")
    widget = resource(:Widget, "AshR2RML.SemanticGraphQLDfCMTest.Widget", "widgets")

    widget =
      Map.put(widget, :relationships, [
        %{
          name: :owner,
          predicate_iri: "https://migration.example/ontology/owner",
          source_class: widget.class_iri,
          target_class: owner.class_iri,
          min_count: 0,
          max_count: 1,
          storage_strategy: nil
        }
      ])

    profile = %{
      ontology_hash: "ontology:sha256:migration",
      profile_hash: "profile:sha256:migration",
      shacl_hash: "shacl:sha256:migration",
      resources: [widget, owner]
    }

    assert {:ok, bundle} = AshR2RML.compile_api_bundle(profile, graphql: true)

    schema = bundle.files["generated/graphql/schema.graphql"]
    manifest = Jason.decode!(bundle.files["generated/graphql/semantic-manifest.json"])
    receipt = Jason.decode!(bundle.files["receipts/graphql-projection.json"])

    assert schema =~ "type Widget {"
    assert schema =~ "owner: Owner"
    assert schema =~ "type Owner {"
    refute schema =~ "Mutation"
    refute schema =~ "Subscription"
    refute schema =~ "rename"

    assert manifest["mode"] == "read_only"
    assert manifest["action_projection"] == false
    assert manifest["authority"] == "none"
    assert manifest["consequence_path"] == "brce"
    assert manifest["policy_enforcement"] == "external"
    assert manifest["runtime_execution"] == "external"
    assert manifest["backend_selection"] == "unselected"

    widget_manifest =
      Enum.find(manifest["resources"], fn resource ->
        resource["class_iri"] == widget.class_iri
      end)

    assert Enum.any?(widget_manifest["fields"], fn field ->
             field["semantic_kind"] == "object_property" and
               field["predicate_iri"] == "https://migration.example/ontology/owner" and
               field["target_class"] == owner.class_iri
           end)

    assert widget_manifest["excluded_consequence_actions"] == [
             %{
               "name" => "rename",
               "kind" => "update",
               "projected" => false,
               "consequence_path" => "brce"
             }
           ]

    assert widget_manifest["policy_obligations"] == [
             %{
               "name" => "viewer_scope",
               "effect" => "permit",
               "odrl_iri" => "https://migration.example/policy/viewer-scope",
               "enforcement" => "external",
               "source" => "semantic_ir"
             }
           ]

    assert receipt["authority"] == "none"
    assert receipt["action_projection"] == false
    assert receipt["policy_enforcement"] == "external"
    assert receipt["observed"] == []
    assert receipt["executed"] == []
    assert receipt["verified"] == []
  end
end

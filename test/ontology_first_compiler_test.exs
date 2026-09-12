# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OntologyFirstCompilerTest do
  use ExUnit.Case, async: true

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"
  @xsd_decimal "http://www.w3.org/2001/XMLSchema#decimal"

  defp profile(overrides \\ %{}) do
    base = %{
      ontology_hash: "ontology:sha256:aaa",
      profile_hash: "profile:sha256:bbb",
      shacl_hash: "shacl:sha256:ccc",
      resources: [
        %{
          iri: "https://xaas.example/resource/Organization",
          class_iri: "https://www.w3.org/ns/org#Organization",
          shape_iri: "https://xaas.example/shapes/OrganizationShape",
          module: "Xaas.Organization",
          repo_module: "Xaas.Repo",
          table: "organizations",
          subject_template: "https://xaas.example/id/organization/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://xaas.example/ontology/id",
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
          ]
        },
        %{
          iri: "https://xaas.example/resource/Account",
          class_iri: "https://spec.edmcouncil.org/fibo/ontology/FBC/FinancialPositions/FinancialPositions/Account",
          shape_iri: "https://xaas.example/shapes/AccountShape",
          module: "Xaas.Account",
          repo_module: "Xaas.Repo",
          table: "accounts",
          subject_template: "https://xaas.example/id/account/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              predicate_iri: "https://xaas.example/ontology/id",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false,
              identity?: true
            },
            %{
              name: :organization_id,
              predicate_iri: "https://xaas.example/ontology/organizationId",
              datatype_iri: @xsd_string,
              ash_type: :uuid,
              postgres_type: "UUID",
              min_count: 1,
              max_count: 1,
              nullable: false
            },
            %{
              name: :account_number,
              predicate_iri: "https://xaas.example/ontology/accountNumber",
              datatype_iri: @xsd_string,
              min_count: 1,
              max_count: 1
            },
            %{
              name: :balance,
              predicate_iri: "https://xaas.example/ontology/balance",
              datatype_iri: @xsd_decimal,
              min_count: 1,
              max_count: 1
            }
          ],
          relationships: [
            %{
              name: :organization,
              predicate_iri: "https://www.w3.org/ns/org#memberOf",
              source_class:
                "https://spec.edmcouncil.org/fibo/ontology/FBC/FinancialPositions/FinancialPositions/Account",
              target_class: "https://www.w3.org/ns/org#Organization",
              min_count: 1,
              max_count: 1,
              storage_strategy: :foreign_key,
              source_key: :organization_id,
              destination_key: :id
            }
          ],
          actions: [%{name: :reconcile, kind: :update, provenance: %{source: "xaas-profile"}}],
          policies: [
            %{
              name: :account_access,
              effect: :authorize,
              odrl_iri: "http://www.w3.org/ns/odrl/2/permission"
            }
          ]
        }
      ]
    }

    Map.merge(base, overrides)
  end

  test "one admitted profile converges on canonical mapping before all projections" do
    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile())

    assert compilation.status == :PARTIAL_ALIVE
    assert compilation.standing == :constructed_not_actuated
    assert %AshR2RML.Mapping.Bundle{} = compilation.mapping_bundle
    assert length(compilation.mapping_bundle.resources) == 2

    assert compilation.ash_source =~ "defmodule Xaas.Account"
    assert compilation.ash_source =~ "data_layer: AshPostgres.DataLayer"
    assert compilation.ash_source =~ "belongs_to :organization, Xaas.Organization"

    assert compilation.ecto_migration =~ "use Ecto.Migration"
    assert compilation.ecto_migration =~ "references(:\"organizations\""

    assert compilation.postgres_ddl =~ ~s(CREATE TABLE IF NOT EXISTS "accounts")

    assert compilation.postgres_ddl =~
             ~s{FOREIGN KEY ("organization_id") REFERENCES "organizations" ("id")}

    organization_mapping =
      Enum.find(compilation.mapping_bundle.resources, &(&1.ash_resource == "Xaas.Organization"))

    organization_map_iri = AshR2RML.Mapping.mapping_identity(organization_mapping)

    assert compilation.r2rml =~ "rr:TriplesMap"
    assert compilation.r2rml =~ "rr:parentTriplesMap <#{organization_map_iri}>"
    refute compilation.r2rml =~ "<#Xaas_Organization>"

    assert compilation.r2rml =~
             ~s(rr:joinCondition [ rr:child "organization_id"; rr:parent "id" ])

    assert compilation.shacl =~ "sh:targetClass <https://www.w3.org/ns/org#Organization>"
    assert compilation.shacl =~ "sh:minCount 1; sh:maxCount 1"

    assert compilation.receipt.classes_admitted == 2
    assert compilation.receipt.relationships_admitted == 1
    assert compilation.receipt.actions_admitted == 1
    assert compilation.receipt.policies_admitted == 1
    assert is_binary(compilation.receipt.mapping_sha256)
    assert is_binary(compilation.receipt.ecto_sha256)
    assert :canonical_mapping_ir in compilation.receipt.executed
    assert :canonical_mapping_ir_projection in compilation.receipt.verified
    assert compilation.receipt.query_parity == :UNKNOWN
    refute AshR2RML.Compiler.cutover_ready?(compilation.receipt)
  end

  test "DfCM preserves ambiguous lawful storage candidates and refuses premature projection" do
    ambiguous =
      update_in(profile(), [:resources], fn resources ->
        Enum.map(resources, fn
          %{module: "Xaas.Account"} = account ->
            update_in(account, [:relationships], fn [relationship | rest] ->
              [Map.put(relationship, :storage_strategy, nil) | rest]
            end)

          other ->
            other
        end)
      end)

    assert {:ok, ir} = AshR2RML.Compiler.explore(ambiguous)
    account = Enum.find(ir.resources, &(&1.module == "Xaas.Account"))
    relationship = hd(account.relationships)

    assert relationship.storage_strategy == nil
    assert :foreign_key in relationship.storage_candidates
    assert :association_resource in relationship.storage_candidates

    assert {:error, compilation} = AshR2RML.Compiler.compile(ambiguous)
    assert compilation.status == :REFUSED
    assert Enum.any?(compilation.refusals, &(&1.code == :REFUSED_UNPROVEN_EQUIVALENCE))
  end

  test "unknown datatype is refused unless its projections are explicitly admitted" do
    broken =
      update_resource("Xaas.Account", fn account ->
        update_in(account, [:attributes], fn attrs ->
          Enum.map(attrs, fn
            %{name: :balance} = balance ->
              balance
              |> Map.put(:datatype_iri, "https://example.com/datatype/Money")
              |> Map.delete(:ash_type)
              |> Map.delete(:postgres_type)

            other ->
              other
          end)
        end)
      end)

    assert {:error, compilation} = AshR2RML.Compiler.compile(broken)
    assert Enum.any?(compilation.refusals, &(&1.code == :REFUSED_DATATYPE_CAST_NOT_LOSSLESS))
  end

  test "single-column R2RML parent join identity cannot be inferred from a composite identity" do
    broken =
      update_resource("Xaas.Organization", fn organization ->
        organization
        |> Map.put(:subject_template, "https://xaas.example/id/organization/{id}/{name}")
        |> Map.put(:identities, [%{name: :primary, keys: [:id, :name], primary?: true}])
      end)

    assert {:error, compilation} = AshR2RML.Compiler.compile(broken)
    assert Enum.any?(compilation.refusals, &(&1.code == :REFUSED_R2RML_JOIN_KEY_NOT_UNIQUE))
  end

  test "multiple primary semantic identities are refused" do
    broken =
      update_resource("Xaas.Organization", fn organization ->
        Map.put(organization, :identities, [
          %{name: :primary, keys: [:id], primary?: true},
          %{name: :alternate_primary, keys: [:name], primary?: true}
        ])
      end)

    assert {:error, compilation} = AshR2RML.Compiler.compile(broken)
    assert Enum.any?(compilation.refusals, &(&1.code == :REFUSED_NON_UNIQUE_SEMANTIC_IDENTITY))
  end

  test "SHACL minCount and relational nullability must remain concordant" do
    broken =
      update_resource("Xaas.Account", fn account ->
        update_in(account, [:attributes], fn attrs ->
          Enum.map(attrs, fn
            %{name: :balance} = balance -> Map.put(balance, :nullable, true)
            other -> other
          end)
        end)
      end)

    assert {:error, compilation} = AshR2RML.Compiler.compile(broken)
    assert Enum.any?(compilation.refusals, &(&1.code == :REFUSED_CARDINALITY_STORAGE_MISMATCH))
  end

  test "projection identity is deterministic independent of input ordering" do
    assert {:ok, first} = AshR2RML.Compiler.compile(profile())

    reordered =
      profile()
      |> update_in([:resources], fn resources ->
        resources
        |> Enum.reverse()
        |> Enum.map(fn resource ->
          resource
          |> Map.update(:attributes, [], &Enum.reverse/1)
          |> Map.update(:relationships, [], &Enum.reverse/1)
          |> Map.update(:identities, [], &Enum.reverse/1)
          |> Map.update(:actions, [], &Enum.reverse/1)
          |> Map.update(:policies, [], &Enum.reverse/1)
        end)
      end)

    assert {:ok, second} = AshR2RML.Compiler.compile(reordered)

    assert first.receipt.ir_sha256 == second.receipt.ir_sha256
    assert first.receipt.mapping_sha256 == second.receipt.mapping_sha256
    assert first.receipt.ash_sha256 == second.receipt.ash_sha256
    assert first.receipt.ecto_sha256 == second.receipt.ecto_sha256
    assert first.receipt.postgres_sha256 == second.receipt.postgres_sha256
    assert first.receipt.r2rml_sha256 == second.receipt.r2rml_sha256
    assert first.receipt.shacl_sha256 == second.receipt.shacl_sha256
  end

  test "cutover requires external query parity and separate authority" do
    assert {:ok, compilation} = AshR2RML.Compiler.compile(profile())

    receipt =
      compilation.receipt
      |> AshR2RML.Compiler.attach_parity_witness(:sparql_sql, %{
        verified?: true,
        receipt_sha256: "sparql-sql-receipt"
      })

    assert receipt.query_parity == :VERIFIED
    refute AshR2RML.Compiler.cutover_ready?(receipt)
    assert :cutover_authority in receipt.blocked
  end

  defp update_resource(module, fun) do
    update_in(profile(), [:resources], fn resources ->
      Enum.map(resources, fn
        %{module: ^module} = resource -> fun.(resource)
        other -> other
      end)
    end)
  end
end

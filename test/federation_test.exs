# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FederationTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Federation
  alias AshR2RML.Federation.{Environment, FederationReceipt}
  alias AshR2RML.Refusal

  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  defp profile(ontology_hash \\ "ontology:sha256:federation-aaa") do
    %{
      ontology_hash: ontology_hash,
      profile_hash: "profile:sha256:federation-bbb",
      shacl_hash: "shacl:sha256:federation-ccc",
      resources: [
        %{
          iri: "https://fed.example/resource/Organization",
          class_iri: "https://www.w3.org/ns/org#Organization",
          shape_iri: "https://fed.example/shapes/OrganizationShape",
          module: "Fed.Organization",
          repo_module: "Fed.Repo",
          table: "organizations",
          subject_template: "https://fed.example/id/organization/{id}",
          identities: [%{name: :primary, keys: [:id], primary?: true}],
          attributes: [
            %{
              name: :id,
              column: "id",
              predicate_iri: "https://fed.example/ontology/id",
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
        }
      ]
    }
  end

  defp environment(name, ontology_sha256 \\ "ontology:sha256:federation-aaa") do
    {:ok, env} =
      Federation.admit_environment(%{
        name: name,
        compiler_version: "ash_r2rml-test-1",
        admitted_ontology_sha256: ontology_sha256
      })

    env
  end

  describe "admit_environment/1" do
    test "admits a well-formed environment config" do
      assert {:ok, %Environment{name: "us-east", compiler_version: "v1", admitted_ontology_sha256: "sha"}} =
               Federation.admit_environment(%{
                 name: "us-east",
                 compiler_version: "v1",
                 admitted_ontology_sha256: "sha"
               })
    end

    test "refuses a config missing :name" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               Federation.admit_environment(%{compiler_version: "v1", admitted_ontology_sha256: "sha"})
    end

    test "refuses a config with an empty :compiler_version" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               Federation.admit_environment(%{
                 name: "us-east",
                 compiler_version: "",
                 admitted_ontology_sha256: "sha"
               })
    end

    test "refuses a non-map config" do
      assert {:error, %Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}} =
               Federation.admit_environment("not-a-map")
    end
  end

  describe "compile_for_environments/2 -- determinism across identical environments" do
    test "compiling the same profile across 3 identically-admitted environments produces byte-identical artifacts" do
      environments = [environment("us-east"), environment("eu-west"), environment("ap-south")]

      receipt = Federation.compile_for_environments(profile(), environments)

      assert %FederationReceipt{all_identical?: true, refusals: []} = receipt
      assert receipt.environments == ["us-east", "eu-west", "ap-south"]
      assert receipt.diverging_environments == []

      shas = Map.values(receipt.artifact_sha256_by_environment)
      assert length(shas) == 3
      assert length(Enum.uniq(shas)) == 1
      assert Enum.all?(shas, &is_binary/1)
    end
  end

  describe "compile_for_environments/2 -- real divergence detection" do
    test "an environment admitted against a different ontology identity is named as diverging, not silently averaged away" do
      environments = [
        environment("us-east"),
        environment("eu-west"),
        environment("ap-south", "ontology:sha256:DIFFERENT")
      ]

      receipt = Federation.compile_for_environments(profile(), environments)

      refute receipt.all_identical?
      assert "ap-south" in receipt.diverging_environments
      assert Enum.any?(receipt.refusals, fn %Refusal{subject: subject} -> subject == "ap-south" end)

      # the two genuinely identical environments still agree with each other
      agreeing_shas =
        receipt.artifact_sha256_by_environment
        |> Map.take(["us-east", "eu-west"])
        |> Map.values()

      assert length(Enum.uniq(agreeing_shas)) == 1
      refute Map.has_key?(receipt.artifact_sha256_by_environment, "ap-south")
    end

    test "an empty environment list is refused rather than silently vacuously true" do
      receipt = Federation.compile_for_environments(profile(), [])

      refute receipt.all_identical?
      assert [%Refusal{code: :REFUSED_INVALID_FEDERATION_ENVIRONMENT}] = receipt.refusals
    end
  end
end

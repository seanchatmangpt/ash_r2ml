# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML do
  @moduledoc """
  Semantic mapping compiler between Ash resources and W3C R2RML.

  AshR2RML is not an Ash data layer and never owns persistence. Ash-first and
  ontology-first inputs converge on `AshR2RML.Mapping.Bundle`; R2RML is then a
  deterministic projection of that normalized IR. RDF serialization and SPARQL
  execution remain explicit boundary choices rather than alternate sources of
  truth.
  """

  @r2rml %Spark.Dsl.Section{
    name: :r2rml,
    describe: "W3C R2RML mapping metadata for an Ash resource",
    schema: [
      class_iri: [type: :string, required: true],
      subject_template: [type: :string, required: true],
      table_name: [type: :string, required: false],
      sql_query: [type: :string, required: false],
      graph_iri: [type: :string, required: false],
      attribute_mappings: [type: {:list, {:tuple, [:atom, :string]}}, required: false, default: []],
      typed_attribute_mappings: [type: {:list, {:tuple, [:atom, :string, :string]}}, required: false, default: []],
      relationship_mappings: [type: {:list, {:tuple, [:atom, :string]}}, required: false, default: []]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@r2rml],
    transformers: [AshR2RML.PersistMapping],
    verifiers: [AshR2RML.VerifyMapping]

  @doc "Compile one Ash resource into its normalized semantic mapping."
  defdelegate mapping(resource), to: AshR2RML.Resource.Info

  @doc "Compile one or more Ash resources or profile map into a closed bundle."
  defdelegate compile(resources_or_profile), to: AshR2RML.Compiler, as: :compile

  @doc "Compile an admitted profile into a manufactured ggen bundle."
  defdelegate compile_bundle(profile), to: AshR2RML.Ggen

  @doc "Emit ontology, SHACL, and R2RML TTL for cloud ggen directly from Ash resources."
  defdelegate compile_ash_ttl_bundle(resources_or_bundle), to: AshR2RML.Ggen

  @doc "Inspect normalized AshR2RML resource mapping."
  defdelegate mapping_result(resource), to: AshR2RML.Resource.Info

  @doc "Parse RDF/Turtle + SHACL into the normalized closed ontology-first profile."
  def ingest_turtle(turtle, opts \\ []), do: AshR2RML.Ingestion.from_turtle(turtle, opts)

  @doc "Compile RDF/Turtle + SHACL into the same canonical mapping bundle as Ash-first resources."
  def compile_turtle(turtle, opts \\ []), do: AshR2RML.Ingestion.compile_turtle(turtle, opts)

  @doc "Compile RDF/Turtle + SHACL directly into the deterministic ggen bundle."
  def compile_turtle_bundle(turtle, opts \\ []), do: AshR2RML.Ggen.compile_turtle_bundle(turtle, opts)

  @doc "Parse JSON-LD 1.1 + SHACL into the normalized closed ontology-first profile."
  def ingest_jsonld(jsonld, opts \\ []), do: AshR2RML.JSONLD.ingest(jsonld, opts)

  @doc "Compile JSON-LD 1.1 + SHACL into the same canonical mapping bundle as Turtle and Ash-first resources."
  def compile_jsonld(jsonld, opts \\ []), do: AshR2RML.JSONLD.compile(jsonld, opts)

  @doc "Compile JSON-LD 1.1 + SHACL directly into the deterministic ggen bundle."
  def compile_jsonld_bundle(jsonld, opts \\ []), do: AshR2RML.Ggen.compile_jsonld_bundle(jsonld, opts)

  @doc "Admit and identify a SPARQL query without executing it."
  defdelegate admit_sparql(query), to: AshR2RML.SPARQL.Query, as: :admit

  @doc "Load and admit a SPARQL .rq query file from disk."
  defdelegate load_sparql_file(path), to: AshR2RML.SPARQL.Query, as: :load_file

  @doc "Explore all supplied lawful SPARQL execution candidates without prematurely selecting among them."
  def plan_sparql(query, opts \\ []), do: AshR2RML.SPARQL.explore(query, opts)

  @doc "Execute an explicitly selected or uniquely forced SPARQL execution plan."
  defdelegate execute_sparql(plan), to: AshR2RML.SPARQL, as: :execute

  @doc "Admit normalized Knowledge Hook definitions into a construct-only plan."
  def admit_knowledge_hooks(definitions, opts \\ []),
    do: AshR2RML.KnowledgeHooks.admit(definitions, opts)

  @doc "Parse canonical AshR2RML, GitVan, or KNHK Knowledge Hook Turtle into a construct-only plan."
  def ingest_knowledge_hooks_turtle(turtle, opts \\ []),
    do: AshR2RML.KnowledgeHook.Ingestion.from_turtle(turtle, opts)

  @doc "Evaluate admitted Knowledge Hooks and construct unauthorized intents for matches."
  def evaluate_knowledge_hooks(plan, opts \\ []),
    do: AshR2RML.KnowledgeHooks.evaluate(plan, opts)

  @doc "Compile an admitted Knowledge Hook plan to canonical content-addressed hook IR."
  def compile_knowledge_hook_specs(plan), do: AshR2RML.KnowledgeHook.Spec.from_plan(plan)

  @doc "Deterministically order canonical Knowledge Hook specs by explicit dependencies."
  def schedule_knowledge_hook_specs(specs), do: AshR2RML.KnowledgeHook.Scheduler.schedule(specs)

  @doc "Project a constructed Knowledge Hook intent to a typed inert downstream target."
  def project_knowledge_hook_target(intent), do: AshR2RML.KnowledgeHook.Target.from_intent(intent)

  @doc "Evaluate cognition-to-reflex promotion evidence without granting actuation authority."
  def evaluate_knowledge_hook_promotion(candidate, evidence, opts \\ []),
    do: AshR2RML.KnowledgeHook.Promotion.evaluate(candidate, evidence, opts)

  @doc "Manufacture a deterministic ggen path/content bundle for admitted Knowledge Hooks."
  def compile_knowledge_hooks_bundle(plan_or_definitions, opts \\ []),
    do: AshR2RML.Ggen.KnowledgeHooks.compile(plan_or_definitions, opts)

  @doc "Parse canonical/legacy Knowledge Hook Turtle and manufacture its deterministic ggen path/content bundle."
  def compile_knowledge_hooks_turtle_bundle(turtle, opts \\ []),
    do: AshR2RML.Ggen.KnowledgeHooks.compile_turtle(turtle, opts)

  @doc "Render standards-oriented R2RML Turtle from a bundle or Ash resource set."
  defdelegate render(resources_or_bundle), to: AshR2RML.R2RML

  @doc "Render standards-oriented R2RML Turtle from a bundle or Ash resource set."
  defdelegate render_r2rml(resources_or_bundle), to: AshR2RML.R2RML, as: :render

  @doc "Render SHACL shapes graph from a bundle or Ash resource set."
  defdelegate render_shacl(resources_or_bundle), to: AshR2RML.SHACL, as: :render

  @doc "Validate and return compilation receipt for resources or profile."
  def validate(resources_or_profile) do
    case AshR2RML.Compiler.compile(resources_or_profile) do
      {:ok, %AshR2RML.Compilation{receipt: receipt}} ->
        receipt

      {:error, %AshR2RML.Compilation{receipt: receipt}} ->
        receipt

      {:ok, %AshR2RML.Mapping.Bundle{} = bundle} ->
        {:ok, r2rml} = AshR2RML.R2RML.render(bundle)
        {:ok, shacl} = AshR2RML.SHACL.render(bundle)

        %AshR2RML.CompilationReceipt{
          status: :PARTIAL_ALIVE,
          standing: :constructed_not_actuated,
          mapping_sha256: AshR2RML.Compiler.sha256(bundle),
          r2rml_sha256: AshR2RML.Compiler.sha256(r2rml),
          shacl_sha256: AshR2RML.Compiler.sha256(shacl),
          query_parity: :UNKNOWN,
          neo4j_postgres_parity: :UNKNOWN,
          cutover_authority: :UNAUTHORIZED,
          classes_admitted: length(bundle.resources),
          executed: [:canonical_mapping_ir, :r2rml_render, :shacl_render],
          verified: [:canonical_mapping_ir_projection],
          blocked: [:sparql_sql_behavioral_parity, :neo4j_postgres_semantic_parity, :cutover_authority],
          refusals: []
        }

      {:error, %AshR2RML.Refusal{} = refusal} ->
        %AshR2RML.CompilationReceipt{
          status: :REFUSED,
          standing: :no_cutover,
          refusals: [refusal]
        }
    end
  end
end

defmodule AshR2RML.Validation do
  @moduledoc false
  defdelegate cutover_ready?(receipt), to: AshR2RML.Compiler
end

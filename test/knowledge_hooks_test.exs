# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHooks

  @ask_query """
  ASK WHERE {
    <https://example.com/thing> <https://example.com/state> <https://example.com/ready>
  }
  """

  @select_query """
  SELECT ?state WHERE {
    <https://example.com/thing> <https://example.com/state> ?state
  }
  """

  @gitvan_turtle """
  @prefix ex: <https://example.com/> .
  @prefix gv: <https://gitvan.dev/ontology#> .
  @prefix gh: <https://gitvan.dev/graph-hook#> .
  @prefix op: <https://gitvan.dev/op#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

  ex:ready-hook rdf:type gh:Hook ;
      gv:title "Ready hook" ;
      gh:hasPredicate ex:ready-predicate ;
      gh:orderedPipelines ex:ready-pipeline .

  ex:ready-predicate rdf:type gh:ASKPredicate ;
      gh:queryText "ASK WHERE { <https://example.com/thing> <https://example.com/state> <https://example.com/ready> }" .

  ex:ready-pipeline rdf:type op:Pipeline .
  """

  @knhk_turtle """
  @prefix ex: <https://example.com/> .
  @prefix knhk: <http://knhk.io/ontology#> .
  @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

  ex:event-hook rdf:type knhk:Hook ;
      knhk:name "Event hook" ;
      knhk:triggerType "Event" ;
      knhk:triggerPattern "repository:changed" ;
      knhk:action "workflow://reindex" ;
      knhk:emitReceipt true .
  """

  test "normalized ASK hooks are content-addressed and construct intents without authority" do
    definitions = [
      %{
        id: "ready-hook",
        name: "Ready hook",
        trigger_type: :sparql_result,
        predicate: %{type: :ask, query: @ask_query},
        intent: %{kind: :pipeline, target: "pipeline://ready", payload: %{mode: "safe"}}
      }
    ]

    assert {:ok, first} = KnowledgeHooks.admit(definitions, source_identity: %{profile_hash: "profile-1"})
    assert {:ok, second} = KnowledgeHooks.admit(definitions, source_identity: %{profile_hash: "profile-1"})
    assert first.plan_sha256 == second.plan_sha256
    assert first.authority == :UNAUTHORIZED
    assert first.standing == :admitted_construct_only

    graph =
      RDF.Graph.new([
        {RDF.iri("https://example.com/thing"), RDF.iri("https://example.com/state"),
         RDF.iri("https://example.com/ready")}
      ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(first,
               current: [data: graph, strategy: :local_rdf]
             )

    assert evaluation.matched?
    assert evaluation.intent.target == "pipeline://ready"
    assert evaluation.intent.authority == :UNAUTHORIZED
    assert evaluation.intent.standing == :constructed_not_actuated
    assert evaluation.intent.requires_actuation_receipt?
    assert evaluation.receipt.authority == :UNAUTHORIZED
    assert evaluation.receipt.consequence == :intent_constructed
    assert evaluation.receipt.blocked == [:actuation_authority]
    assert is_binary(evaluation.receipt.receipt_sha256)
    assert byte_size(evaluation.receipt.receipt_sha256) == 64
  end

  test "false ASK predicates emit observation receipts but no intent" do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "ready-hook",
                 name: "Ready hook",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: "pipeline://ready"
               }
             ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan,
               current: [data: RDF.Graph.new(), strategy: :local_rdf]
             )

    refute evaluation.matched?
    assert evaluation.intent == nil
    assert evaluation.receipt.standing == :observed_predicate_only
    assert evaluation.receipt.consequence == :none
  end

  test "result-delta predicates compare independently observed result identities" do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "state-change",
                 name: "State change",
                 trigger_type: :sparql_result,
                 predicate: %{type: :result_delta, query: @select_query},
                 intent: %{kind: :workflow, target: "workflow://state-change"}
               }
             ])

    previous =
      RDF.Graph.new([
        {RDF.iri("https://example.com/thing"), RDF.iri("https://example.com/state"),
         RDF.iri("https://example.com/pending")}
      ])

    current =
      RDF.Graph.new([
        {RDF.iri("https://example.com/thing"), RDF.iri("https://example.com/state"),
         RDF.iri("https://example.com/ready")}
      ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan,
               previous: [data: previous, strategy: :local_rdf],
               current: [data: current, strategy: :local_rdf]
             )

    assert evaluation.matched?
    assert evaluation.receipt.previous_result_sha256 != evaluation.receipt.current_result_sha256
    assert length(evaluation.observations) == 2
  end

  test "result-delta does not fire when semantic query results are unchanged" do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "state-change",
                 name: "State change",
                 trigger_type: :sparql_result,
                 predicate: %{type: :result_delta, query: @select_query},
                 intent: "workflow://state-change"
               }
             ])

    graph =
      RDF.Graph.new([
        {RDF.iri("https://example.com/thing"), RDF.iri("https://example.com/state"),
         RDF.iri("https://example.com/ready")}
      ])

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan,
               previous: [data: graph, strategy: :local_rdf],
               current: [data: graph, strategy: :local_rdf]
             )

    refute evaluation.matched?
    assert evaluation.intent == nil
    assert evaluation.receipt.previous_result_sha256 == evaluation.receipt.current_result_sha256
  end

  test "GitVan Graph Hook Turtle is admitted without importing pipeline execution authority" do
    assert {:ok, plan} = KnowledgeHooks.from_turtle(@gitvan_turtle)
    assert [hook] = plan.hooks
    assert hook.id == "https://example.com/ready-hook"
    assert hook.predicate.type == :ask
    assert hook.intent.kind == :pipeline
    assert hook.intent.target == "https://example.com/ready-pipeline"
    assert hook.require_actuation_receipt?

    projection = KnowledgeHooks.projection(plan)
    assert projection.authority == :UNAUTHORIZED
    assert [projected] = projection.hooks
    assert projected.authority == :UNAUTHORIZED
    assert projected.standing == :construct_only
  end

  test "KNHK event hooks require an external observed trigger receipt" do
    assert {:ok, plan} = KnowledgeHooks.from_turtle(@knhk_turtle)
    assert [hook] = plan.hooks
    assert hook.trigger_type == :event
    assert hook.predicate.type == :external_trigger

    assert {:error, refusal} = KnowledgeHooks.evaluate(plan)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE

    assert {:ok, [evaluation]} =
             KnowledgeHooks.evaluate(plan,
               trigger_receipts: %{
                 "https://example.com/event-hook" => %{
                   observed?: true,
                   receipt_sha256: String.duplicate("a", 64)
                 }
               }
             )

    assert evaluation.matched?
    assert evaluation.intent.target == "workflow://reindex"
    assert evaluation.receipt.external_trigger_receipt_sha256 == String.duplicate("a", 64)
    assert evaluation.intent.authority == :UNAUTHORIZED
  end

  test "ggen knowledge-hook bundle is deterministic construct-only output" do
    assert {:ok, plan} = KnowledgeHooks.from_turtle(@gitvan_turtle)
    assert {:ok, bundle} = AshR2RML.Ggen.KnowledgeHooks.compile(plan)

    assert bundle.status == :PARTIAL_ALIVE
    assert bundle.standing == :construct_only
    assert bundle.authority == :UNAUTHORIZED
    assert bundle.knowledge_hook_plan_sha256 == plan.plan_sha256
    assert Map.has_key?(bundle.files, "generated/knowledge-hooks/plan.json")
    assert Map.has_key?(bundle.files, "receipts/knowledge-hooks-compilation.json")

    plan_json = Jason.decode!(bundle.files["generated/knowledge-hooks/plan.json"])
    assert plan_json["authority"] == "UNAUTHORIZED"
    assert get_in(plan_json, ["hooks", Access.at(0), "standing"]) == "construct_only"
  end
end

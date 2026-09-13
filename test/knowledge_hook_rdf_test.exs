# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHookRDFTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHook.{Ingestion, Spec}

  @canonical_turtle """
  @prefix kh: <https://seanchatmangpt.github.io/ash-r2rml/knowledge-hook#> .
  @prefix ex: <https://example.com/> .
  @prefix dct: <http://purl.org/dc/terms/> .

  ex:customerReadyHook
    a kh:Hook ;
    dct:title "Customer ready" ;
    kh:trigger ex:customerReadyTrigger ;
    kh:observation ex:customerObservation ;
    kh:predicate ex:customerReadyPredicate ;
    kh:construct ex:customerReadyConstruct ;
    kh:receiptPolicy ex:receiptPolicy ;
    kh:authorityCeiling "CONSTRUCT" .

  ex:customerReadyTrigger
    a kh:Trigger ;
    kh:triggerType "sparql_result" .

  ex:customerObservation
    a kh:Observation .

  ex:customerReadyPredicate
    a kh:Predicate ;
    kh:predicateType "ask" ;
    kh:queryText "ASK WHERE { <https://example.com/customer/42> <https://example.com/state> <https://example.com/ready> }" .

  ex:customerReadyConstruct
    a kh:Construct ;
    kh:constructKind "reactor" ;
    kh:target "MyApp.CustomerReadyReactor" .

  ex:receiptPolicy
    a kh:ReceiptPolicy ;
    kh:requiresEvaluationReceipt true ;
    kh:requiresActuationReceipt true ;
    kh:requiresConsequenceReceipt true .
  """

  test "canonical RDF lowers to the same construct-only admitted plan and Spec IR" do
    assert {:ok, plan} = Ingestion.from_turtle(@canonical_turtle)
    assert plan.authority == :UNAUTHORIZED
    assert [hook] = plan.hooks
    assert hook.id == "https://example.com/customerReadyHook"
    assert hook.predicate.type == :ask
    assert hook.intent.kind == :reactor
    assert hook.intent.target == "MyApp.CustomerReadyReactor"
    assert hook.provenance.source == :ash_r2rml_knowledge_hook

    assert {:ok, [spec]} = Spec.from_plan(plan)
    assert spec.authority_ceiling == :CONSTRUCT
    assert spec.construct.kind == :reactor
    assert spec.construct.target == "MyApp.CustomerReadyReactor"
    assert spec.observation.projection.node == "https://example.com/customerObservation"
  end

  test "native vocabulary cannot raise the authority ceiling" do
    turtle = String.replace(@canonical_turtle, "kh:authorityCeiling \"CONSTRUCT\"", "kh:authorityCeiling \"DO\"")

    assert {:error, [refusal]} = Ingestion.from_turtle(turtle)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.detail =~ "authority ceiling"
  end

  test "native vocabulary cannot disable any receipt boundary" do
    turtle = String.replace(@canonical_turtle, "kh:requiresActuationReceipt true", "kh:requiresActuationReceipt false")

    assert {:error, [refusal]} = Ingestion.from_turtle(turtle)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.detail =~ "receipt policy"
  end

  test "legacy GitVan and KNHK remain routed through the established interoperability adapter" do
    legacy = """
    @prefix gh: <https://gitvan.dev/graph-hook#> .
    @prefix gv: <https://gitvan.dev/ontology#> .
    @prefix ex: <https://example.com/> .

    ex:hook a gh:Hook ;
      gv:title "Ready" ;
      gh:hasPredicate ex:predicate ;
      gh:orderedPipelines ex:pipeline .

    ex:predicate a gh:ASKPredicate ;
      gh:queryText "ASK WHERE { <https://example.com/a> <https://example.com/p> <https://example.com/b> }" .
    """

    assert {:ok, plan} = Ingestion.from_turtle(legacy)
    assert [hook] = plan.hooks
    assert hook.provenance.source == :gitvan_graph_hook
    assert hook.intent.kind == :pipeline
  end
end

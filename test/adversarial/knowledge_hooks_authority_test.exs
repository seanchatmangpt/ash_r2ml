# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksAuthorityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHooks

  @ask_query "ASK WHERE { <https://example.com/a> <https://example.com/p> <https://example.com/b> }"

  test "refuses executable callbacks at the knowledge-hook boundary" do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "ambient-do",
                 name: "Ambient DO",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: "workflow://unsafe",
                 callback: fn -> :actuate end
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == "ambient-do"
    assert :callback in refusal.evidence.forbidden_keys
  end

  test "refuses hook definitions that attempt to disable downstream actuation receipts" do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "unreceipted",
                 name: "Unreceipted",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: "workflow://unsafe",
                 require_actuation_receipt?: false
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == "unreceipted"
  end

  test "refuses unsupported GitVan predicate types instead of approximating semantics" do
    turtle = """
    @prefix ex: <https://example.com/> .
    @prefix gh: <https://gitvan.dev/graph-hook#> .
    @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .

    ex:threshold rdf:type gh:Hook ;
        gh:hasPredicate ex:threshold-predicate ;
        gh:orderedPipelines ex:pipeline .

    ex:threshold-predicate rdf:type gh:SELECTThreshold ;
        gh:queryText "SELECT ?n WHERE { ?s ?p ?n }" .
    """

    assert {:error, [refusal]} = KnowledgeHooks.from_turtle(turtle)
    assert refusal.code == :REFUSED_UNSUPPORTED_SPARQL_FEATURE
    assert refusal.subject == "https://example.com/threshold"
  end

  test "opaque intent payloads may carry data but not runtime handles" do
    assert {:error, [refusal]} =
             KnowledgeHooks.admit([
               %{
                 id: "function-in-payload",
                 name: "Function in payload",
                 predicate: %{type: :ask, query: @ask_query},
                 intent: %{
                   kind: :workflow,
                   target: "workflow://unsafe",
                   payload: %{runner: fn _ -> :actuate end}
                 }
               }
             ])

    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    assert refusal.subject == "function-in-payload"
  end
end

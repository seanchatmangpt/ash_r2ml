# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksSHACLThresholdCountTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHooks

  @conforming_shapes """
  @prefix ex: <https://example.com/> .
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

  ex:PersonShape
      a sh:NodeShape ;
      sh:targetNode ex:alice ;
      sh:property [
          sh:path ex:name ;
          sh:minCount 1 ;
          sh:maxCount 1 ;
          sh:datatype xsd:string
      ] .
  """

  @threshold_query """
  SELECT ?count WHERE {
    <https://example.com/metrics> <https://example.com/errorCount> ?count
  }
  """

  @count_query """
  SELECT ?item WHERE {
    ?item <https://example.com/state> <https://example.com/failed>
  }
  """

  describe ":shacl predicate" do
    test "conforming focus node fires true and constructs an intent" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "shacl-conform",
                   name: "SHACL conform",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :shacl,
                     shapes_graph: @conforming_shapes,
                     focus: "https://example.com/alice"
                   },
                   intent: %{kind: :workflow, target: "workflow://shacl-conform"}
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/name"),
           RDF.literal("Alice")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      assert evaluation.matched?
      assert evaluation.intent.target == "workflow://shacl-conform"
      assert evaluation.intent.authority == :UNAUTHORIZED
      assert evaluation.receipt.consequence == :intent_constructed
    end

    test "violating focus node fires false and emits no intent" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "shacl-violate",
                   name: "SHACL violate",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :shacl,
                     shapes_graph: @conforming_shapes,
                     focus: "https://example.com/alice"
                   },
                   intent: "workflow://shacl-violate"
                 }
               ])

      # ex:alice has no ex:name triple at all -> minCount 1 violated.
      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/other"),
           RDF.literal("irrelevant")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      refute evaluation.matched?
      assert evaluation.intent == nil
      assert evaluation.receipt.standing == :observed_predicate_only
      assert evaluation.receipt.consequence == :none
    end

    test "admission is blocked when the SHACL predicate has no focus node" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "shacl-no-focus",
                   name: "SHACL no focus",
                   trigger_type: :sparql_result,
                   predicate: %{type: :shacl, shapes_graph: @conforming_shapes, focus: ""},
                   intent: "workflow://shacl-no-focus"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_SHACL_SHAPES_GRAPH}] = refusals
    end
  end

  describe ":threshold predicate" do
    test "value above the bound fires true" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "threshold-over",
                   name: "Threshold over",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :threshold,
                     query: @threshold_query,
                     comparator: :gt,
                     bound: 10
                   },
                   intent: %{kind: :workflow, target: "workflow://threshold-alert"}
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/metrics"), RDF.iri("https://example.com/errorCount"),
           RDF.literal(42)}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      assert evaluation.matched?
      assert evaluation.intent.target == "workflow://threshold-alert"
      assert evaluation.receipt.consequence == :intent_constructed
    end

    test "value at or below the bound fires false" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "threshold-under",
                   name: "Threshold under",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :threshold,
                     query: @threshold_query,
                     comparator: :gt,
                     bound: 10
                   },
                   intent: "workflow://threshold-alert"
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/metrics"), RDF.iri("https://example.com/errorCount"),
           RDF.literal(3)}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      refute evaluation.matched?
      assert evaluation.intent == nil
      assert evaluation.receipt.consequence == :none
    end

    test "admission is blocked for an unsupported comparator" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "threshold-bad-comparator",
                   name: "Threshold bad comparator",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :threshold,
                     query: @threshold_query,
                     comparator: :nope,
                     bound: 10
                   },
                   intent: "workflow://threshold-alert"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_BOUND_PREDICATE}] = refusals
    end
  end

  describe ":count predicate" do
    test "row count above the bound fires true" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "count-over",
                   name: "Count over",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :count,
                     query: @count_query,
                     comparator: :gte,
                     bound: 2
                   },
                   intent: %{kind: :workflow, target: "workflow://count-alert"}
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/item1"), RDF.iri("https://example.com/state"),
           RDF.iri("https://example.com/failed")},
          {RDF.iri("https://example.com/item2"), RDF.iri("https://example.com/state"),
           RDF.iri("https://example.com/failed")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      assert evaluation.matched?
      assert evaluation.intent.target == "workflow://count-alert"
      assert evaluation.receipt.consequence == :intent_constructed
    end

    test "row count below the bound fires false" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "count-under",
                   name: "Count under",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :count,
                     query: @count_query,
                     comparator: :gte,
                     bound: 2
                   },
                   intent: "workflow://count-alert"
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/item1"), RDF.iri("https://example.com/state"),
           RDF.iri("https://example.com/failed")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      refute evaluation.matched?
      assert evaluation.intent == nil
      assert evaluation.receipt.consequence == :none
    end

    test "admission is blocked when the query form is not SELECT" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "count-ask-form",
                   name: "Count ask form",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :count,
                     query: "ASK WHERE { <https://example.com/a> <https://example.com/b> <https://example.com/c> }",
                     comparator: :gte,
                     bound: 1
                   },
                   intent: "workflow://count-alert"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}] = refusals
    end
  end
end

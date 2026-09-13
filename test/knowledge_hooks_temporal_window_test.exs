# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksTemporalWindowTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHooks

  @temporal_query """
  SELECT ?occurredAt WHERE {
    <https://example.com/event1> <https://example.com/occurredAt> ?occurredAt
  }
  """

  defp admit_temporal_window(comparator, bound, unit \\ :hour) do
    KnowledgeHooks.admit([
      %{
        id: "temporal-window-1",
        name: "Temporal window",
        trigger_type: :sparql_result,
        predicate: %{
          type: :temporal_window,
          query: @temporal_query,
          window: {unit, comparator, bound},
          time_field: "occurredAt"
        },
        intent: %{kind: :workflow, target: "workflow://temporal-window"}
      }
    ])
  end

  describe ":temporal_window predicate" do
    test "time within the window fires true and constructs an intent" do
      assert {:ok, plan} = admit_temporal_window(:lte, 24)

      evaluated_at = ~U[2026-09-12 12:00:00Z]
      # 2 hours before evaluated_at -> well within a 24h window.
      occurred_at = ~U[2026-09-12 10:00:00Z]

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/event1"), RDF.iri("https://example.com/occurredAt"), RDF.literal(occurred_at)}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan,
                 current: [data: data, strategy: :local_rdf],
                 evaluated_at: evaluated_at
               )

      assert evaluation.matched?
      assert evaluation.intent.target == "workflow://temporal-window"
      assert evaluation.receipt.consequence == :intent_constructed
      assert evaluation.receipt.predicate_type == :temporal_window
    end

    test "time outside the window fires false and emits no intent" do
      assert {:ok, plan} = admit_temporal_window(:lte, 24)

      evaluated_at = ~U[2026-09-12 12:00:00Z]
      # 48 hours before evaluated_at -> outside a 24h window.
      occurred_at = ~U[2026-09-10 12:00:00Z]

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/event1"), RDF.iri("https://example.com/occurredAt"), RDF.literal(occurred_at)}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan,
                 current: [data: data, strategy: :local_rdf],
                 evaluated_at: evaluated_at
               )

      refute evaluation.matched?
      assert evaluation.intent == nil
      assert evaluation.receipt.standing == :observed_predicate_only
      assert evaluation.receipt.consequence == :none
    end

    test "unparseable time_field value is blocked with evidence" do
      assert {:ok, plan} = admit_temporal_window(:lte, 24)

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/event1"), RDF.iri("https://example.com/occurredAt"),
           RDF.literal("not-a-datetime")}
        ])

      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_BOUND_PREDICATE} = refusal} =
               KnowledgeHooks.evaluate(plan,
                 current: [data: data, strategy: :local_rdf],
                 evaluated_at: ~U[2026-09-12 12:00:00Z]
               )

      assert refusal.evidence.time_field == "occurredAt"
      assert refusal.evidence.value =~ "not-a-datetime"
    end

    test "missing evaluated_at is refused at evaluation, never falling back to wall-clock time" do
      assert {:ok, plan} = admit_temporal_window(:lte, 24)

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/event1"), RDF.iri("https://example.com/occurredAt"),
           RDF.literal(~U[2026-09-12 10:00:00Z])}
        ])

      assert {:error, %AshR2RML.Refusal{code: :REFUSED_MISSING_EVALUATION_TIME} = refusal} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      assert refusal.subject == "temporal-window-1"
    end

    test "admission is blocked for a malformed window spec" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "temporal-window-bad-window",
                   name: "Temporal window bad window",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :temporal_window,
                     query: @temporal_query,
                     window: {:fortnight, :lte, 24},
                     time_field: "occurredAt"
                   },
                   intent: "workflow://temporal-window"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_BOUND_PREDICATE}] = refusals
    end

    test "admission is blocked when the query form is not SELECT" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "temporal-window-ask-form",
                   name: "Temporal window ask form",
                   trigger_type: :sparql_result,
                   predicate: %{
                     type: :temporal_window,
                     query: "ASK WHERE { <https://example.com/a> <https://example.com/b> <https://example.com/c> }",
                     window: {:hour, :lte, 24},
                     time_field: "occurredAt"
                   },
                   intent: "workflow://temporal-window"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_UNSUPPORTED_SPARQL_FEATURE}] = refusals
    end
  end
end

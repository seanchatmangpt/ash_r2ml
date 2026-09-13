# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHooksDatalogTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHooks

  @grandparent_rule """
  grandparent(?x, ?z) :- (?x, <https://example.com/parentOf>, ?y), (?y, <https://example.com/parentOf>, ?z).
  """

  describe ":datalog predicate" do
    test "a real single-rule join over a real RDF.Graph fires true" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "datalog-grandparent-fires",
                   name: "Grandparent fires",
                   trigger_type: :sparql_result,
                   predicate: %{type: :datalog, rule: @grandparent_rule},
                   intent: %{kind: :workflow, target: "workflow://grandparent-fires"}
                 }
               ])

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/bob")},
          {RDF.iri("https://example.com/bob"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/carol")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      assert evaluation.matched?
      assert evaluation.intent.target == "workflow://grandparent-fires"
      assert evaluation.receipt.consequence == :intent_constructed
    end

    test "a real single-rule join over a real RDF.Graph with no matching chain fires false" do
      assert {:ok, plan} =
               KnowledgeHooks.admit([
                 %{
                   id: "datalog-grandparent-no-fire",
                   name: "Grandparent does not fire",
                   trigger_type: :sparql_result,
                   predicate: %{type: :datalog, rule: @grandparent_rule},
                   intent: "workflow://grandparent-no-fire"
                 }
               ])

      # Only one parentOf hop exists -> no two-hop chain, rule cannot fire.
      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/bob")}
        ])

      assert {:ok, [evaluation]} =
               KnowledgeHooks.evaluate(plan, current: [data: data, strategy: :local_rdf])

      refute evaluation.matched?
      assert evaluation.intent == nil
      assert evaluation.receipt.consequence == :none
    end

    test "admission is blocked for a malformed rule" do
      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "datalog-malformed",
                   name: "Malformed Datalog rule",
                   trigger_type: :sparql_result,
                   predicate: %{type: :datalog, rule: "this is not a rule at all"},
                   intent: "workflow://datalog-malformed"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_DATALOG_RULE}] = refusals
    end

    test "admission is blocked for a recursive rule" do
      recursive_rule = """
      ancestor(?x, ?y) :- (?x, ancestor, ?y).
      """

      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "datalog-recursive",
                   name: "Recursive Datalog rule",
                   trigger_type: :sparql_result,
                   predicate: %{type: :datalog, rule: recursive_rule},
                   intent: "workflow://datalog-recursive"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_DATALOG_RULE}] = refusals
    end

    test "admission is blocked for an unsafe rule (head variable not bound in body)" do
      unsafe_rule = """
      result(?x, ?w) :- (?x, <https://example.com/parentOf>, ?y).
      """

      assert {:error, refusals} =
               KnowledgeHooks.admit([
                 %{
                   id: "datalog-unsafe",
                   name: "Unsafe Datalog rule",
                   trigger_type: :sparql_result,
                   predicate: %{type: :datalog, rule: unsafe_rule},
                   intent: "workflow://datalog-unsafe"
                 }
               ])

      assert [%AshR2RML.Refusal{code: :REFUSED_INVALID_DATALOG_RULE}] = refusals
    end
  end

  describe "AshR2RML.KnowledgeHook.Datalog directly" do
    alias AshR2RML.KnowledgeHook.Datalog

    test "admit_rule/1 and evaluate/3 fire true on a real matching graph" do
      assert {:ok, rule} = Datalog.admit_rule(@grandparent_rule)

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/bob")},
          {RDF.iri("https://example.com/bob"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/carol")}
        ])

      assert {:ok, bindings} = Datalog.evaluate(rule, data, [])
      assert bindings == [%{"x" => "https://example.com/alice", "z" => "https://example.com/carol"}]
    end

    test "evaluate/3 returns [] (NotFired) on a real non-matching graph" do
      assert {:ok, rule} = Datalog.admit_rule(@grandparent_rule)

      data =
        RDF.Graph.new([
          {RDF.iri("https://example.com/alice"), RDF.iri("https://example.com/parentOf"),
           RDF.iri("https://example.com/bob")}
        ])

      assert {:ok, []} = Datalog.evaluate(rule, data, [])
    end

    test "admit_rule/1 refuses malformed rule text" do
      assert {:error, %AshR2RML.Refusal{code: :REFUSED_INVALID_DATALOG_RULE}} =
               Datalog.admit_rule("not a rule")
    end
  end
end

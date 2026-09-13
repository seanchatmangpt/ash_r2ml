# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHookSpecTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHook.{Scheduler, Spec, Target}
  alias AshR2RML.KnowledgeHooks

  @ask "ASK WHERE { <https://example.com/a> <https://example.com/p> <https://example.com/b> }"

  test "admitted hooks compile to deterministic construct-only specs" do
    definitions = [
      %{
        id: "observe",
        name: "Observe",
        predicate: %{type: :ask, query: @ask},
        intent: %{kind: :reactor, target: "MyApp.ReadyReactor", payload: %{id: 42}},
        provenance: %{observation_projection: %{subject: "https://example.com/a"}}
      }
    ]

    assert {:ok, plan} = KnowledgeHooks.admit(definitions)
    assert {:ok, [first]} = Spec.from_plan(plan)
    assert {:ok, [second]} = Spec.from_plan(plan)

    assert first.spec_sha256 == second.spec_sha256
    assert first.authority_ceiling == :CONSTRUCT
    assert first.receipt_policy.evaluation_required?
    assert first.receipt_policy.actuation_required?
    assert first.receipt_policy.consequence_required?

    projection = Spec.projection(first)
    assert projection.authority == :UNAUTHORIZED
    assert projection.authority_ceiling == :CONSTRUCT
    assert projection.construct.target == "MyApp.ReadyReactor"
  end

  test "dependency scheduler is deterministic and refuses missing dependencies" do
    definitions = [
      %{
        id: "a",
        name: "A",
        predicate: %{type: :ask, query: @ask},
        intent: "workflow://a"
      },
      %{
        id: "b",
        name: "B",
        predicate: %{type: :ask, query: @ask},
        intent: "workflow://b",
        provenance: %{after: ["a"]}
      }
    ]

    assert {:ok, plan} = KnowledgeHooks.admit(definitions)
    assert {:ok, specs} = Spec.from_plan(plan)
    assert {:ok, scheduled} = Scheduler.schedule(Enum.reverse(specs))
    assert Enum.map(scheduled, & &1.id) == ["a", "b"]

    [a, b] = specs
    bad_b = %{b | dependencies: ["missing"]}
    assert {:error, refusal} = Scheduler.schedule([a, bad_b])
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
  end

  test "dependency scheduler refuses cycles" do
    definitions = [
      %{id: "a", name: "A", predicate: %{type: :ask, query: @ask}, intent: "workflow://a"},
      %{id: "b", name: "B", predicate: %{type: :ask, query: @ask}, intent: "workflow://b"}
    ]

    assert {:ok, plan} = KnowledgeHooks.admit(definitions)
    assert {:ok, [a, b]} = Spec.from_plan(plan)
    a = %{a | dependencies: ["b"]}
    b = %{b | dependencies: ["a"]}

    assert {:error, refusal} = Scheduler.schedule([a, b])
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
  end

  test "typed downstream targets remain inert and unauthorized" do
    assert {:ok, reactor} = Target.reactor(MyApp.CustomerReadyReactor, %{customer_id: 42})
    assert reactor.kind == :reactor
    assert reactor.authority == :UNAUTHORIZED
    assert reactor.standing == :constructed_not_actuated
    assert reactor.requires_actuation_receipt?

    assert {:ok, action} = Target.ash_action(MyApp.Customer, :approve, %{id: 42})
    assert action.kind == :ash_action
    assert action.authority == :UNAUTHORIZED

    assert {:ok, transition} = Target.state_transition(MyApp.Customer, :approved, %{id: 42})
    assert transition.kind == :state_transition

    assert {:ok, job} = Target.oban(MyApp.ReindexWorker, %{customer_id: 42}, {:in, 60})
    assert job.kind == :oban
    assert job.metadata.schedule == {:in, 60}
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidenceTest do
  use ExUnit.Case, async: true

  alias AshR2RML.FrontierEvidence
  alias AshR2RML.KnowledgeHook.Ash, as: AshHooks
  alias AshR2RML.KnowledgeHooks
  alias AshR2RML.Refusal

  @producer_head "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "native Ash observation/evaluation evidence projects without adding DO authority" do
    {observations, evaluations} = native_evidence()

    assert {:ok, fragment} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations,
               producer_head: @producer_head
             )

    assert fragment.schema == "frontier-evidence/v1"
    assert fragment.producer == "ash_r2rml"
    assert fragment.producer_head == @producer_head
    assert fragment.standing == "PARTIAL_ALIVE"
    assert fragment.authority_ceiling == "CONSTRUCT"
    assert fragment.artifact_hash =~ ~r/^sha256:[0-9a-f]{64}$/
    assert "callbacks" in fragment.refused
    assert "actuation_authority" in fragment.refused
    assert :ok = FrontierEvidence.verify(fragment)
  end

  test "projection and replay identity are deterministic for identical native evidence" do
    {observations, evaluations} = native_evidence()
    opts = [producer_head: @producer_head]

    assert {:ok, first} = FrontierEvidence.from_knowledge_hooks(observations, evaluations, opts)
    assert {:ok, second} = FrontierEvidence.from_knowledge_hooks(observations, evaluations, opts)

    assert first == second
    assert first.artifact_hash == second.artifact_hash
    assert :ok = FrontierEvidence.verify(first)
  end

  test "refuses observation authority widening and non-observation execution" do
    {[observation], evaluations} = native_evidence()

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               [%{observation | authority: :AUTHORIZED}],
               evaluations,
               producer_head: @producer_head
             )

    assert detail =~ "authority or consequence"

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               [%{observation | executed: [:callback]}],
               evaluations,
               producer_head: @producer_head
             )

    assert detail =~ "execution trace"
  end

  test "refuses widened constructed intent authority" do
    {observations, [evaluation]} = native_evidence()
    widened_intent = %{evaluation.intent | authority: :AUTHORIZED}
    widened_evaluation = %{evaluation | intent: widened_intent}

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [widened_evaluation],
               producer_head: @producer_head
             )

    assert detail =~ "actuation authority"
  end

  test "refuses evaluation consequence or execution outside SELECT/CONSTRUCT" do
    {observations, [evaluation]} = native_evidence()

    consequence_receipt = %{evaluation.receipt | consequence: :actuated}

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [%{evaluation | receipt: consequence_receipt}],
               producer_head: @producer_head
             )

    assert detail =~ "authority/consequence"

    executed_receipt = %{evaluation.receipt | executed: [:external_trigger_witness_admission, :do]}

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [%{evaluation | receipt: executed_receipt}],
               producer_head: @producer_head
             )

    assert detail =~ "execution trace"
  end

  test "refuses evaluation detached from exported observation receipt" do
    {observations, [evaluation]} = native_evidence()

    detached_receipt = %{
      evaluation.receipt
      | external_trigger_receipt_sha256: String.duplicate("f", 64)
    }

    detached_evaluation = %{evaluation | receipt: detached_receipt}

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [detached_evaluation],
               producer_head: @producer_head
             )

    assert detail =~ "detached" or detail =~ "unexported"
  end

  test "refuses malformed producer identity, unsupported options, and self-promotion to ALIVE" do
    {observations, evaluations} = native_evidence()

    assert {:error, %Refusal{subject: :producer_head}} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations,
               producer_head: "moving-ref"
             )

    assert {:error, %Refusal{detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations,
               producer_head: @producer_head,
               callback: &Function.identity/1
             )

    assert detail =~ "unsupported options"

    assert {:error, %Refusal{subject: :standing, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations,
               producer_head: @producer_head,
               standing: "ALIVE"
             )

    assert detail =~ "self-promote"
  end

  test "replay verifier refuses content, authority, and refusal-envelope tampering" do
    {observations, evaluations} = native_evidence()

    assert {:ok, fragment} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations,
               producer_head: @producer_head
             )

    assert {:error, %Refusal{detail: detail}} =
             fragment
             |> put_in([:evidence, :evaluations], [])
             |> FrontierEvidence.verify()

    assert detail =~ "does not replay"

    assert {:error, %Refusal{detail: detail}} =
             fragment
             |> Map.put(:authority_ceiling, "DO")
             |> FrontierEvidence.verify()

    assert detail =~ "widened"

    assert {:error, %Refusal{detail: detail}} =
             fragment
             |> Map.put(:refused, ["callbacks"])
             |> FrontierEvidence.verify()

    assert detail =~ "refusal envelope"
  end

  defp native_evidence do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "frontier-evidence-action",
                 name: "FrontierEvidence observed Ash action",
                 trigger_type: :event,
                 trigger_pattern: %{
                   source: :ash_action,
                   span_type: :action,
                   name: "organization.update"
                 },
                 intent: %{
                   kind: :workflow,
                   target: "workflow://frontier-evidence-test"
                 }
               }
             ])

    span = %Ash.Tracer.Simple.Span{
      type: :action,
      id: "frontier-span-1",
      parent_id: "frontier-root-1",
      name: "organization.update",
      start: 1_789_174_000_000
    }

    assert {:ok, %{observations: observations, evaluations: evaluations}} =
             AshHooks.evaluate(plan, span)

    {observations, evaluations}
  end
end

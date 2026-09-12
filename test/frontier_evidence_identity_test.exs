# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidenceIdentityTest do
  use ExUnit.Case, async: true

  alias AshR2RML.FrontierEvidence
  alias AshR2RML.KnowledgeHook.Ash, as: AshHooks
  alias AshR2RML.KnowledgeHooks
  alias AshR2RML.Refusal

  @producer_head "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "refuses an observation whose native receipt no longer replays" do
    {[observation], evaluations, triggers} = native_evidence()
    tampered = %{observation | subject: Map.put(observation.subject, :name, "tampered.action")}

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             FrontierEvidence.from_knowledge_hooks([tampered], evaluations, triggers,
               producer_head: @producer_head
             )

    assert detail =~ "replay descriptor" or detail =~ "does not replay"
  end

  test "refuses duplicate observation and evaluation identities" do
    {[observation], [evaluation], triggers} = native_evidence()

    assert {:error, %Refusal{detail: observation_detail}} =
             FrontierEvidence.from_knowledge_hooks(
               [observation, observation],
               [evaluation],
               triggers,
               producer_head: @producer_head
             )

    assert observation_detail =~ "duplicate observation identity"

    assert {:error, %Refusal{detail: evaluation_detail}} =
             FrontierEvidence.from_knowledge_hooks(
               [observation],
               [evaluation, evaluation],
               triggers,
               producer_head: @producer_head
             )

    assert evaluation_detail =~ "duplicate evaluation receipt identity"
  end

  test "refuses repeated observation identity inside an explicit trigger receipt" do
    {observations, evaluations, triggers} = native_evidence()
    [{hook_id, trigger}] = Map.to_list(triggers)
    [receipt_sha256] = trigger.observation_receipts

    repeated =
      Map.put(triggers, hook_id, %{
        trigger
        | observation_receipts: [receipt_sha256, receipt_sha256]
      })

    assert {:error, %Refusal{detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations, repeated,
               producer_head: @producer_head
             )

    assert detail =~ "repeats an observation identity"
  end

  test "refuses an evaluation receipt whose identity or digest is recombined" do
    {observations, [evaluation], triggers} = native_evidence()

    wrong_identity =
      %{evaluation.receipt | identity: Map.put(evaluation.receipt.identity, :hook_id, "other-hook")}

    assert {:error, %Refusal{detail: identity_detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [%{evaluation | receipt: wrong_identity}],
               triggers,
               producer_head: @producer_head
             )

    assert identity_detail =~ "identity descriptor"

    wrong_digest = %{evaluation.receipt | receipt_sha256: String.duplicate("f", 64)}

    assert {:error, %Refusal{detail: digest_detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [%{evaluation | receipt: wrong_digest}],
               triggers,
               producer_head: @producer_head
             )

    assert digest_detail =~ "receipt identity does not replay"
  end

  test "refuses a constructed intent detached from its evaluation hook identity" do
    {observations, [evaluation], triggers} = native_evidence()
    detached_intent = %{evaluation.intent | hook_id: "other-hook"}

    assert {:error, %Refusal{detail: detail}} =
             FrontierEvidence.from_knowledge_hooks(
               observations,
               [%{evaluation | intent: detached_intent}],
               triggers,
               producer_head: @producer_head
             )

    assert detail =~ "hook identity differs"
  end

  defp native_evidence do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "frontier-evidence-identity",
                 name: "FrontierEvidence identity witness",
                 trigger_type: :event,
                 trigger_pattern: %{
                   source: :ash_action,
                   span_type: :action,
                   name: "organization.update"
                 },
                 intent: %{
                   kind: :workflow,
                   target: "workflow://frontier-evidence-identity"
                 }
               }
             ])

    span = %Ash.Tracer.Simple.Span{
      type: :action,
      id: "frontier-identity-span-1",
      parent_id: "frontier-identity-root-1",
      name: "organization.update",
      start: 1_789_174_000_001
    }

    assert {:ok, %{observations: observations, evaluations: evaluations}} =
             AshHooks.evaluate(plan, span)

    assert {:ok, triggers} = AshHooks.trigger_receipts(plan, observations)

    {observations, evaluations, triggers}
  end
end

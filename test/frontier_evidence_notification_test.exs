# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidenceNotificationTest do
  use ExUnit.Case, async: true

  alias AshR2RML.FrontierEvidence
  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.KnowledgeHook.Ash, as: AshHooks
  alias AshR2RML.KnowledgeHooks

  @id "0199a000-0000-7000-8000-000000000001"
  @producer_head "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  test "exports native Ash notification state-change evidence through the same CONSTRUCT ceiling" do
    plan = notification_plan()
    notification = update_notification()

    assert {:ok, %{observations: observations, evaluations: evaluations}} =
             AshHooks.evaluate(plan, notification)

    assert {:ok, trigger_receipts} = AshHooks.trigger_receipts(plan, observations)

    assert {:ok, fragment} =
             FrontierEvidence.from_knowledge_hooks(observations, evaluations, trigger_receipts,
               producer_head: @producer_head
             )

    assert [observation] = observations
    assert observation.source == :ash_notification
    assert observation.subject.action_type == :update
    assert observation.subject.changed_attributes == ["name"]
    assert observation.subject.attribute_delta["name"] == %{from: "before", to: "after"}
    assert observation.subject.primary_key["id"] == @id

    assert fragment.authority_ceiling == "CONSTRUCT"
    assert fragment.standing == "PARTIAL_ALIVE"
    assert :ok = FrontierEvidence.verify(fragment)
  end

  test "notification projection is deterministic for identical native state-change evidence" do
    plan = notification_plan()
    notification = update_notification()

    assert {:ok, first_native} = AshHooks.evaluate(plan, notification)
    assert {:ok, second_native} = AshHooks.evaluate(plan, notification)
    assert {:ok, first_triggers} = AshHooks.trigger_receipts(plan, first_native.observations)
    assert {:ok, second_triggers} = AshHooks.trigger_receipts(plan, second_native.observations)

    assert {:ok, first} =
             FrontierEvidence.from_knowledge_hooks(
               first_native.observations,
               first_native.evaluations,
               first_triggers,
               producer_head: @producer_head
             )

    assert {:ok, second} =
             FrontierEvidence.from_knowledge_hooks(
               second_native.observations,
               second_native.evaluations,
               second_triggers,
               producer_head: @producer_head
             )

    assert first == second
    assert first.artifact_hash == second.artifact_hash
  end

  defp notification_plan do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "frontier-evidence-notification",
                 name: "FrontierEvidence notification witness",
                 trigger_type: :event,
                 trigger_pattern: %{
                   source: :ash_notification,
                   resource: Organization,
                   action: :update,
                   action_type: :update,
                   changed: [:name],
                   transition: %{attribute: :name, from: "before", to: "after"}
                 },
                 intent: %{
                   kind: :workflow,
                   target: "workflow://frontier-evidence-notification"
                 }
               }
             ])

    plan
  end

  defp update_notification do
    changeset = update_changeset()
    after_record = %{changeset.data | name: "after"}

    %Ash.Notifier.Notification{
      resource: Organization,
      domain: Domain,
      action: changeset.action,
      changeset: changeset,
      data: after_record,
      metadata: %{source: :test}
    }
  end

  defp update_changeset do
    before_record = %Organization{id: @id, name: "before", version: "1.0.0"}

    before_record
    |> Ash.Changeset.new()
    |> Ash.Changeset.force_change_attribute(:name, "after")
    |> Ash.Changeset.for_update(:update, %{})
  end
end

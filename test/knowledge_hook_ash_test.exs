# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.AshTest do
  use ExUnit.Case, async: true

  alias AshR2RML.Ggen.KnowledgeHooks, as: GgenKnowledgeHooks
  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.KnowledgeHook.Ash, as: AshHooks
  alias AshR2RML.KnowledgeHooks
  alias AshR2RML.Refusal

  @id "0199a000-0000-7000-8000-000000000001"

  test "Ash notifications become deterministic state-change observations and explicit trigger receipts" do
    plan = notification_plan(%{
      source: :ash_notification,
      resource: Organization,
      action: :update,
      action_type: :update,
      changed: [:name],
      transition: %{attribute: :name, from: "before", to: "after"}
    })

    notification = update_notification()

    assert {:ok, first} = AshHooks.evaluate(plan, notification)
    assert {:ok, second} = AshHooks.evaluate(plan, notification)

    assert [observation] = first.observations
    assert observation == hd(second.observations)
    assert observation.source == :ash_notification
    assert observation.authority == :UNAUTHORIZED
    assert observation.consequence == :none
    assert observation.standing == :observed_ash_primitive
    assert observation.subject.resource == inspect(Organization)
    assert observation.subject.action == "update"
    assert observation.subject.action_type == :update
    assert observation.subject.changed_attributes == ["name"]
    assert observation.subject.attribute_delta["name"] == %{from: "before", to: "after"}
    assert observation.subject.primary_key["id"] == @id
    assert byte_size(observation.receipt_sha256) == 64

    assert [evaluation] = first.evaluations
    assert evaluation.matched?
    assert evaluation.intent.target == "workflow://knowledge-hook-test"
    assert evaluation.intent.authority == :UNAUTHORIZED
    assert evaluation.intent.standing == :constructed_not_actuated
    assert evaluation.receipt.authority == :UNAUTHORIZED
    assert evaluation.receipt.external_trigger_receipt_sha256 ==
             hd(second.evaluations).receipt.external_trigger_receipt_sha256
    assert byte_size(evaluation.receipt.external_trigger_receipt_sha256) == 64
    assert evaluation.receipt.blocked == [:actuation_authority]
  end

  test "standalone changesets and unobserved external trigger maps fail closed" do
    changeset = update_changeset()

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             AshHooks.observe(changeset)

    assert detail =~ "candidate state"

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             AshHooks.observe(%{resource: Organization, action: :update, changed: [:name]})

    assert detail =~ "unsupported or unobserved"
  end

  test "Ash action spans are observed separately from committed state-change notifications" do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "ash-action-observed",
                 name: "Ash action observed",
                 trigger_type: :event,
                 trigger_pattern: %{source: :ash_action, span_type: :action, name: "organization.update"},
                 intent: %{kind: :workflow, target: "workflow://knowledge-hook-test"}
               }
             ])

    span = %Ash.Tracer.Simple.Span{
      type: :action,
      id: "span-1",
      parent_id: "root-1",
      name: "organization.update",
      start: 1_789_174_000_000
    }

    assert {:ok, %{observations: [observation], evaluations: [evaluation]}} = AshHooks.evaluate(plan, span)
    assert observation.source == :ash_action
    assert observation.subject.span_type == :action
    assert observation.consequence == :none
    assert evaluation.matched?
    assert evaluation.intent.authority == :UNAUTHORIZED

    notification_only_plan = notification_plan(%{source: :ash_notification, changed: [:name]})

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             AshHooks.evaluate(notification_only_plan, span)

    assert detail =~ "requires an observed trigger receipt"
  end

  test "unsupported Ash predicates and interval scheduling are refused before evaluation" do
    callback_pattern_plan =
      notification_plan(%{
        source: :ash_notification,
        changed: [:name],
        callback: "Module.function/1"
      })

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             AshHooks.projection(callback_pattern_plan)

    assert detail =~ "unsupported Ash knowledge-hook trigger predicate"

    interval_plan = notification_plan(%{source: :ash_notification, changed: [:name]}, :interval)

    assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE, detail: detail}} =
             AshHooks.projection(interval_plan)

    assert detail =~ "do not create or schedule timers"
  end

  test "ggen emits a deterministic inert Ash observer projection without registering callbacks" do
    plan = notification_plan(%{
      source: :ash_notification,
      resource: Organization,
      action_type: :update,
      changed: [:name]
    })

    assert {:ok, first} = GgenKnowledgeHooks.compile(plan)
    assert {:ok, second} = GgenKnowledgeHooks.compile(plan)

    path = "generated/knowledge-hooks/ash-observers.json"
    assert first.files[path] == second.files[path]
    assert first.ash_observation_projection_sha256 == second.ash_observation_projection_sha256

    projection = Jason.decode!(first.files[path])
    assert projection["authority"] == "UNAUTHORIZED"
    assert projection["authority_ceiling"] == "CONSTRUCT"
    assert projection["standing"] == "construct_only"
    assert projection["blocked"] == [
             "callbacks",
             "timers",
             "unobserved_external_triggers",
             "actuation_authority"
           ]

    assert [observer] = projection["observation_primitives"]
    assert observer["primitive"] == "Ash.Notifier.Notification"
    assert observer["callbacks"] == "REFUSED"
    assert observer["timers"] == "REFUSED"
    assert observer["actuation"] == "REFUSED"
    refute Map.has_key?(observer, "handler")
    refute Map.has_key?(observer, "execute")
  end

  defp notification_plan(pattern, trigger_type \\ :event) do
    assert {:ok, plan} =
             KnowledgeHooks.admit([
               %{
                 id: "ash-notification-state-change",
                 name: "Ash notification state change",
                 trigger_type: trigger_type,
                 trigger_pattern: pattern,
                 intent: %{kind: :workflow, target: "workflow://knowledge-hook-test"}
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

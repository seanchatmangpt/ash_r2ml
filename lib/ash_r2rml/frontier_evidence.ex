# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidence do
  @moduledoc """
  Content-addressed FrontierEvidence v1 projection for observed knowledge-hook data.

  Inputs must be native, already-produced Ash knowledge-hook observation, trigger,
  and evaluation receipts. This module performs no notifier registration, hook
  registration, callback execution, scheduling, file writes, or downstream
  actuation. It admits only evidence that preserves ash_r2rml's
  OBSERVE/SELECT/CONSTRUCT authority ceiling, then manufactures a deterministic
  portable fragment for a downstream admission court such as XaaS.
  """

  alias AshR2RML.KnowledgeHook.{Evaluation, EvaluationReceipt, Intent}
  alias AshR2RML.KnowledgeHook.Ash.ObservationReceipt
  alias AshR2RML.Refusal

  @schema "frontier-evidence/v1"
  @producer "ash_r2rml"
  @authority_ceiling "CONSTRUCT"
  @allowed_options [:producer_head, :standing]
  @allowed_standings ~w(UNKNOWN PARTIAL_ALIVE BLOCKED BUILD_BROKEN UNSUPPORTED)
  @observation_execution [:native_ash_value_observation]
  @trigger_keys [
    :observed?,
    :matched?,
    :receipt_sha256,
    :source,
    :observation_receipts,
    :standing,
    :authority,
    :consequence,
    :blocked
  ]
  @required_refusals [
    "callbacks",
    "timers",
    "hook_registration",
    "unobserved_external_triggers",
    "actuation_authority"
  ]

  @spec from_knowledge_hooks([ObservationReceipt.t()], [Evaluation.t()], map(), keyword()) ::
          {:ok, map()} | {:error, Refusal.t()}
  def from_knowledge_hooks(observations, evaluations, trigger_receipts, opts \\ [])

  def from_knowledge_hooks(observations, evaluations, trigger_receipts, opts)
      when is_list(observations) and is_list(evaluations) and is_map(trigger_receipts) and
             is_list(opts) do
    with :ok <- validate_options(opts),
         {:ok, producer_head} <- producer_head(opts),
         {:ok, standing} <- standing(opts),
         {:ok, observation_receipts} <- validate_observations(observations),
         {:ok, admitted_triggers} <- validate_trigger_receipts(trigger_receipts, observation_receipts),
         :ok <- validate_evaluations(evaluations, admitted_triggers) do
      evidence = %{
        observations: Enum.map(observations, &canonical_term/1),
        trigger_receipts: canonical_term(trigger_receipts),
        evaluations: Enum.map(evaluations, &canonical_term/1)
      }

      body = %{
        schema: @schema,
        producer: @producer,
        producer_head: producer_head,
        standing: standing,
        authority_ceiling: @authority_ceiling,
        evidence: evidence,
        refused: @required_refusals
      }

      {:ok, Map.put(body, :artifact_hash, fingerprint(body))}
    end
  end

  def from_knowledge_hooks(observations, evaluations, trigger_receipts, opts) do
    refusal(
      :frontier_evidence,
      "FrontierEvidence requires observation/evaluation lists, explicit trigger receipts, and keyword options",
      %{
        observations: inspect_type(observations),
        evaluations: inspect_type(evaluations),
        trigger_receipts: inspect_type(trigger_receipts),
        opts: inspect_type(opts)
      }
    )
  end

  @doc "Recompute fragment identity and re-check the immutable authority envelope."
  @spec verify(map()) :: :ok | {:error, Refusal.t()}
  def verify(%{} = fragment) do
    body = Map.delete(fragment, :artifact_hash)
    expected_hash = Map.get(fragment, :artifact_hash)

    cond do
      Map.get(fragment, :schema) != @schema ->
        refusal(:frontier_evidence, "unsupported FrontierEvidence schema", %{schema: Map.get(fragment, :schema)})

      Map.get(fragment, :producer) != @producer ->
        refusal(:frontier_evidence, "FrontierEvidence producer identity changed", %{producer: Map.get(fragment, :producer)})

      Map.get(fragment, :authority_ceiling) != @authority_ceiling ->
        refusal(:frontier_evidence, "FrontierEvidence authority ceiling widened", %{
          authority_ceiling: Map.get(fragment, :authority_ceiling),
          admitted: @authority_ceiling
        })

      Map.get(fragment, :refused) != @required_refusals ->
        refusal(:frontier_evidence, "FrontierEvidence refusal envelope changed", %{
          refused: Map.get(fragment, :refused),
          admitted: @required_refusals
        })

      not sha256_prefixed?(expected_hash) ->
        refusal(:frontier_evidence, "FrontierEvidence artifact identity is malformed", %{artifact_hash: expected_hash})

      expected_hash != fingerprint(body) ->
        refusal(:frontier_evidence, "FrontierEvidence artifact identity does not replay", %{
          expected: expected_hash,
          replayed: fingerprint(body)
        })

      true ->
        :ok
    end
  end

  def verify(other),
    do: refusal(:frontier_evidence, "FrontierEvidence fragment must be a map", %{got: inspect_type(other)})

  defp validate_options(opts) do
    if Keyword.keyword?(opts) do
      unknown = Keyword.keys(opts) -- @allowed_options

      if unknown == [] do
        :ok
      else
        refusal(:frontier_evidence, "FrontierEvidence received unsupported options", %{unsupported: unknown})
      end
    else
      refusal(:frontier_evidence, "FrontierEvidence options must be a keyword list", %{got: inspect(opts)})
    end
  end

  defp producer_head(opts) do
    case Keyword.fetch(opts, :producer_head) do
      {:ok, head} when is_binary(head) ->
        if Regex.match?(~r/\A[0-9a-f]{40}\z/, head) do
          {:ok, head}
        else
          refusal(:producer_head, "producer_head must be an exact 40-character lowercase Git SHA", %{got: head})
        end

      {:ok, other} ->
        refusal(:producer_head, "producer_head must be an exact Git SHA", %{got: inspect(other)})

      :error ->
        refusal(:producer_head, "producer_head is required for FrontierEvidence identity")
    end
  end

  defp standing(opts) do
    value = Keyword.get(opts, :standing, "PARTIAL_ALIVE")
    value = if is_atom(value), do: Atom.to_string(value), else: value

    if value in @allowed_standings do
      {:ok, value}
    else
      refusal(:standing, "FrontierEvidence cannot self-promote beyond bounded non-DO standing", %{
        got: value,
        admitted: @allowed_standings
      })
    end
  end

  defp validate_observations([]),
    do: refusal(:observations, "FrontierEvidence requires at least one observed Ash primitive")

  defp validate_observations(observations) do
    observations
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {observation, index}, {:ok, receipts} ->
      case validate_observation(observation, index) do
        :ok -> {:cont, {:ok, MapSet.put(receipts, observation.receipt_sha256)}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp validate_observation(%ObservationReceipt{} = receipt, index) do
    cond do
      not sha256?(receipt.receipt_sha256) ->
        evidence_refusal(:observation, index, "observation receipt identity is malformed", receipt)

      receipt.source not in [:ash_notification, :ash_action] ->
        evidence_refusal(:observation, index, "observation source is not a native admitted Ash primitive", receipt)

      not is_map(receipt.subject) or not is_map(receipt.replay) ->
        evidence_refusal(:observation, index, "observation subject/replay identity is incomplete", receipt)

      receipt.version != 1 or receipt.observed? != true or receipt.status != :PARTIAL_ALIVE ->
        evidence_refusal(:observation, index, "observation receipt status is outside the admitted native contract", receipt)

      receipt.standing != :observed_ash_primitive ->
        evidence_refusal(:observation, index, "observation standing is not observed_ash_primitive", receipt)

      receipt.authority != :UNAUTHORIZED or receipt.consequence != :none ->
        evidence_refusal(:observation, index, "observation carries authority or consequence outside OBSERVE", receipt)

      receipt.executed != @observation_execution ->
        evidence_refusal(
          :observation,
          index,
          "observation execution trace is outside the admitted native observation transform",
          receipt
        )

      :observation_receipt_identity not in receipt.verified ->
        evidence_refusal(:observation, index, "observation identity was not verified by the native adapter", receipt)

      :actuation_authority not in receipt.blocked ->
        evidence_refusal(:observation, index, "observation does not explicitly block actuation authority", receipt)

      true ->
        :ok
    end
  end

  defp validate_observation(other, index),
    do:
      refusal(:observations, "FrontierEvidence accepts native Ash observation receipts only", %{
        index: index,
        got: inspect_type(other)
      })

  defp validate_trigger_receipts(trigger_receipts, observation_receipts) do
    Enum.reduce_while(trigger_receipts, {:ok, %{}}, fn {hook_id, trigger}, {:ok, acc} ->
      case validate_trigger_receipt(hook_id, trigger, observation_receipts) do
        :ok -> {:cont, {:ok, Map.put(acc, hook_id, trigger)}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp validate_trigger_receipt(hook_id, trigger, observation_receipts)
       when is_binary(hook_id) and hook_id != "" and is_map(trigger) do
    unknown_keys = Map.keys(trigger) -- @trigger_keys
    refs = Map.get(trigger, :observation_receipts)
    matched? = Map.get(trigger, :matched?)
    expected_consequence = if matched? == true, do: :intent_selection_eligible, else: :none

    cond do
      unknown_keys != [] ->
        refusal(:trigger_receipts, "native Ash trigger receipt contains unsupported fields", %{
          hook_id: hook_id,
          unsupported: unknown_keys
        })

      Map.get(trigger, :observed?) != true or not is_boolean(matched?) ->
        trigger_refusal(hook_id, "trigger receipt observation/match state is malformed", trigger)

      not sha256?(Map.get(trigger, :receipt_sha256)) ->
        trigger_refusal(hook_id, "trigger receipt identity is malformed", trigger)

      Map.get(trigger, :source) != :ash_native_observation ->
        trigger_refusal(hook_id, "trigger receipt source is not the native Ash observation rail", trigger)

      Map.get(trigger, :standing) != :observed_trigger_match_only ->
        trigger_refusal(hook_id, "trigger receipt standing is outside OBSERVE/SELECT", trigger)

      Map.get(trigger, :authority) != :UNAUTHORIZED or
          Map.get(trigger, :consequence) != expected_consequence ->
        trigger_refusal(hook_id, "trigger receipt authority/consequence is outside OBSERVE/SELECT", trigger)

      :actuation_authority not in List.wrap(Map.get(trigger, :blocked)) ->
        trigger_refusal(hook_id, "trigger receipt does not explicitly block actuation authority", trigger)

      not is_list(refs) or refs == [] or not Enum.all?(refs, &sha256?/1) ->
        trigger_refusal(hook_id, "trigger receipt observation identities are malformed", trigger)

      not Enum.all?(refs, &MapSet.member?(observation_receipts, &1)) ->
        trigger_refusal(hook_id, "trigger receipt references an unexported Ash observation", trigger)

      true ->
        :ok
    end
  end

  defp validate_trigger_receipt(hook_id, trigger, _observation_receipts),
    do:
      refusal(:trigger_receipts, "FrontierEvidence accepts native Ash trigger receipts keyed by hook id", %{
        hook_id: inspect(hook_id),
        got: inspect_type(trigger)
      })

  defp validate_evaluations(evaluations, admitted_triggers) do
    evaluations
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {evaluation, index}, :ok ->
      case validate_evaluation(evaluation, index, admitted_triggers) do
        :ok -> {:cont, :ok}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
  end

  defp validate_evaluation(
         %Evaluation{receipt: %EvaluationReceipt{} = receipt} = evaluation,
         index,
         admitted_triggers
       ) do
    with :ok <- validate_evaluation_receipt(evaluation, receipt, index, admitted_triggers),
         :ok <- validate_intent(evaluation, receipt, index) do
      :ok
    end
  end

  defp validate_evaluation(other, index, _admitted_triggers),
    do:
      refusal(:evaluations, "FrontierEvidence accepts native knowledge-hook evaluations only", %{
        index: index,
        got: inspect_type(other)
      })

  defp validate_evaluation_receipt(evaluation, receipt, index, admitted_triggers) do
    expected_standing =
      if evaluation.matched?, do: :constructed_intent_not_actuated, else: :observed_predicate_only

    expected_consequence = if evaluation.matched?, do: :intent_constructed, else: :none
    expected_execution = evaluation_execution(receipt.predicate_type)

    cond do
      not sha256?(receipt.receipt_sha256) or not sha256?(receipt.plan_sha256) ->
        evidence_refusal(:evaluation, index, "evaluation/plan receipt identity is malformed", receipt)

      evaluation.hook_id != receipt.hook_id or not is_binary(evaluation.hook_id) or evaluation.hook_id == "" ->
        evidence_refusal(:evaluation, index, "evaluation hook identity does not match its receipt", receipt)

      not is_boolean(evaluation.matched?) or evaluation.matched? != receipt.matched? ->
        evidence_refusal(:evaluation, index, "evaluation match state does not match its receipt", receipt)

      receipt.status != :PARTIAL_ALIVE or receipt.standing != expected_standing ->
        evidence_refusal(:evaluation, index, "evaluation standing is outside the admitted SELECT/CONSTRUCT contract", receipt)

      receipt.authority != :UNAUTHORIZED or receipt.consequence != expected_consequence ->
        evidence_refusal(:evaluation, index, "evaluation authority/consequence is outside the admitted SELECT/CONSTRUCT contract", receipt)

      is_nil(expected_execution) or receipt.executed != expected_execution ->
        evidence_refusal(:evaluation, index, "evaluation execution trace is outside admitted predicate evaluation/intent selection", receipt)

      :evaluation_receipt_identity not in receipt.verified or :predicate_identity not in receipt.verified ->
        evidence_refusal(:evaluation, index, "evaluation identity was not verified by the native evaluator", receipt)

      :actuation_authority not in receipt.blocked ->
        evidence_refusal(:evaluation, index, "evaluation does not explicitly block actuation authority", receipt)

      not is_map(receipt.identity) or not is_map(receipt.replay) ->
        evidence_refusal(:evaluation, index, "evaluation identity/replay evidence is incomplete", receipt)

      receipt.predicate_type == :external_trigger ->
        validate_external_trigger_link(evaluation, receipt, index, admitted_triggers)

      not is_nil(receipt.external_trigger_receipt_sha256) ->
        evidence_refusal(:evaluation, index, "non-external predicate carries an external trigger receipt", receipt)

      true ->
        :ok
    end
  end

  defp validate_external_trigger_link(evaluation, receipt, index, admitted_triggers) do
    case Map.fetch(admitted_triggers, evaluation.hook_id) do
      :error ->
        evidence_refusal(:evaluation, index, "external-trigger evaluation has no exported trigger receipt", receipt)

      {:ok, trigger} ->
        cond do
          receipt.external_trigger_receipt_sha256 != Map.get(trigger, :receipt_sha256) ->
            evidence_refusal(:evaluation, index, "external-trigger evaluation is detached from its trigger receipt", receipt)

          evaluation.matched? != Map.get(trigger, :matched?) ->
            evidence_refusal(:evaluation, index, "external-trigger evaluation match state differs from its trigger receipt", receipt)

          true ->
            :ok
        end
    end
  end

  defp validate_intent(%Evaluation{matched?: false, intent: nil}, _receipt, _index), do: :ok

  defp validate_intent(%Evaluation{matched?: true, intent: %Intent{} = intent}, receipt, index) do
    cond do
      intent.authority != :UNAUTHORIZED ->
        evidence_refusal(:intent, index, "constructed intent carries actuation authority", intent)

      intent.standing != :constructed_not_actuated ->
        evidence_refusal(:intent, index, "constructed intent standing implies consequence", intent)

      intent.requires_actuation_receipt? != true ->
        evidence_refusal(:intent, index, "constructed intent does not require a downstream actuation receipt", intent)

      intent.evaluation_receipt_sha256 != receipt.receipt_sha256 ->
        evidence_refusal(:intent, index, "constructed intent is detached from its evaluation receipt", intent)

      not is_binary(intent.target) or intent.target == "" ->
        evidence_refusal(:intent, index, "constructed intent target is not a stable inert identifier", intent)

      true ->
        :ok
    end
  end

  defp validate_intent(evaluation, _receipt, index),
    do:
      refusal(:evaluations, "evaluation intent shape does not preserve constructed-not-actuated semantics", %{
        index: index,
        matched?: Map.get(evaluation, :matched?),
        intent: inspect_type(Map.get(evaluation, :intent))
      })

  defp evaluation_execution(:external_trigger),
    do: [:external_trigger_witness_admission, :intent_selection]

  defp evaluation_execution(:result_delta),
    do: [:previous_sparql_observation, :current_sparql_observation, :result_delta]

  defp evaluation_execution(:ask), do: [:sparql_observation, :ask_evaluation]
  defp evaluation_execution(_), do: nil

  defp trigger_refusal(hook_id, detail, trigger) do
    refusal(:trigger_receipts, detail, %{
      hook_id: hook_id,
      receipt_sha256: Map.get(trigger, :receipt_sha256),
      authority: Map.get(trigger, :authority),
      consequence: Map.get(trigger, :consequence),
      standing: Map.get(trigger, :standing),
      observation_receipts: Map.get(trigger, :observation_receipts)
    })
  end

  defp evidence_refusal(kind, index, detail, receipt) do
    refusal(:frontier_evidence, detail, %{
      kind: kind,
      index: index,
      receipt_sha256: Map.get(receipt, :receipt_sha256),
      authority: Map.get(receipt, :authority),
      consequence: Map.get(receipt, :consequence),
      standing: Map.get(receipt, :standing),
      executed: Map.get(receipt, :executed)
    })
  end

  defp refusal(subject, detail, evidence \\ %{}) do
    {:error, Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, subject, detail, evidence)}
  end

  defp fingerprint(term) do
    term
    |> canonical_term()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&("sha256:" <> &1))
  end

  defp canonical_term(%_{} = struct), do: struct |> Map.from_struct() |> canonical_term()

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), canonical_term(value)} end)
    |> Enum.sort()
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)

  defp canonical_term(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&canonical_term/1)

  defp canonical_term(nil), do: nil
  defp canonical_term(value) when is_boolean(value), do: value
  defp canonical_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical_term(other), do: other

  defp sha256?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp sha256_prefixed?(value), do: is_binary(value) and Regex.match?(~r/\Asha256:[0-9a-f]{64}\z/, value)

  defp inspect_type(%module{}), do: inspect(module)
  defp inspect_type(value), do: inspect(value)
end

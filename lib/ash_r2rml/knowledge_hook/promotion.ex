# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Promotion.Evidence do
  @moduledoc "Observed evidence offered to the Knowledge Hook promotion court."

  @enforce_keys [:receipt_sha256]
  defstruct [
    :receipt_sha256,
    :subject,
    :scope,
    :policy_sha256,
    :verifier_sha256,
    standing: :UNKNOWN,
    positive?: false,
    falsifier?: false,
    postcondition_verified?: false,
    replay_verified?: false,
    observed?: false
  ]
end

defmodule AshR2RML.KnowledgeHook.Promotion.Candidate do
  @moduledoc "Candidate learned behavior proposed for deterministic reflex evaluation."

  @enforce_keys [:hook_spec_sha256, :subject, :scope, :policy_sha256, :verifier_sha256]
  defstruct [
    :hook_spec_sha256,
    :subject,
    :scope,
    :policy_sha256,
    :verifier_sha256,
    class: :construct,
    compensation: nil,
    direct_do?: false,
    embedded_authority?: false,
    authority: :UNAUTHORIZED
  ]
end

defmodule AshR2RML.KnowledgeHook.Promotion.Receipt do
  @moduledoc "Receipt proving only promotion-candidate standing, never actuation authority."

  @enforce_keys [:receipt_sha256, :hook_spec_sha256, :evidence_receipts]
  defstruct [
    :receipt_sha256,
    :hook_spec_sha256,
    :evidence_receipts,
    :positive_count,
    :falsifier_count,
    :envelope_sha256,
    status: :PARTIAL_ALIVE,
    standing: :promotion_candidate,
    authority: :UNAUTHORIZED,
    blocked: [:actuation_authority]
  ]
end

defmodule AshR2RML.KnowledgeHook.Promotion do
  @moduledoc """
  Evidence-bounded cognition-to-reflex promotion calculus.

  Promotion recognizes that a bounded distinction has enough evidence to be a
  deterministic hook candidate. It never grants DO authority and never starts a
  Reactor, Ash action, state transition, scheduler, or job.
  """

  alias AshR2RML.KnowledgeHook.Promotion.{Candidate, Evidence, Receipt}
  alias AshR2RML.{Compiler, Refusal}

  @doc "Evaluate a candidate against observed positive and falsifier evidence."
  def evaluate(candidate, evidence, opts \\ [])

  def evaluate(%Candidate{} = candidate, evidence, opts) when is_list(evidence) and is_list(opts) do
    minimum_positive = Keyword.get(opts, :minimum_positive, 2)
    minimum_falsifiers = Keyword.get(opts, :minimum_falsifiers, 1)

    with :ok <- candidate_boundary(candidate),
         :ok <- evidence_identity(evidence),
         :ok <- evidence_envelope(candidate, evidence),
         :ok <- evidence_quality(evidence),
         :ok <- minimum_evidence(evidence, minimum_positive, minimum_falsifiers) do
      evidence_receipts = evidence |> Enum.map(& &1.receipt_sha256) |> Enum.sort()
      positives = Enum.count(evidence, & &1.positive?)
      falsifiers = Enum.count(evidence, & &1.falsifier?)

      envelope = %{
        subject: candidate.subject,
        scope: candidate.scope,
        policy_sha256: candidate.policy_sha256,
        verifier_sha256: candidate.verifier_sha256
      }

      core = %{
        hook_spec_sha256: candidate.hook_spec_sha256,
        class: candidate.class,
        envelope: envelope,
        evidence_receipts: evidence_receipts,
        positive_count: positives,
        falsifier_count: falsifiers,
        authority: :UNAUTHORIZED,
        standing: :promotion_candidate
      }

      receipt = %Receipt{
        receipt_sha256: Compiler.sha256(core),
        hook_spec_sha256: candidate.hook_spec_sha256,
        evidence_receipts: evidence_receipts,
        positive_count: positives,
        falsifier_count: falsifiers,
        envelope_sha256: Compiler.sha256(envelope)
      }

      {:ok,
       %{
         candidate: candidate,
         receipt: receipt,
         authority: :UNAUTHORIZED,
         standing: :promotion_candidate,
         brce_request: brce_request(candidate, receipt)
       }}
    end
  end

  def evaluate(%Candidate{} = _candidate, _evidence, _opts) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :knowledge_hook_promotion,
       "promotion evidence must be a list"
     )}
  end

  @doc "Construct the powerless BRCE request corresponding to a successful promotion receipt."
  def brce_request(%Candidate{} = candidate, %Receipt{} = receipt) do
    %{
      operation: :knowledge_hook_reflex_candidate,
      hook_spec_sha256: candidate.hook_spec_sha256,
      promotion_receipt_sha256: receipt.receipt_sha256,
      subject: candidate.subject,
      scope: candidate.scope,
      policy_sha256: candidate.policy_sha256,
      verifier_sha256: candidate.verifier_sha256,
      compensation: candidate.compensation,
      authority: :UNAUTHORIZED,
      do_authority: false,
      standing: :constructed_not_actuated,
      requires_actuation_receipt?: true
    }
  end

  @doc "Fraction of an initially cognitive episode class eliminated by deterministic closure."
  def cognition_elimination_rate(initial_count, current_count)
      when is_integer(initial_count) and initial_count > 0 and is_integer(current_count) and current_count >= 0 do
    eliminated = max(initial_count - current_count, 0)
    min(eliminated / initial_count, 1.0)
  end

  def cognition_elimination_rate(0, 0), do: 1.0
  def cognition_elimination_rate(_, _), do: 0.0

  defp candidate_boundary(candidate) do
    cond do
      candidate.authority != :UNAUTHORIZED ->
        refusal(candidate, "promotion candidate embeds authority", %{authority: candidate.authority})

      candidate.direct_do? ->
        refusal(candidate, "promotion candidate attempts direct DO", %{direct_do?: true})

      candidate.embedded_authority? ->
        refusal(candidate, "promotion candidate attempts to embed downstream authority", %{embedded_authority?: true})

      candidate.class == :reflex and is_nil(candidate.compensation) ->
        refusal(candidate, "reflex promotion requires an explicit compensation description")

      candidate.class not in [:construct, :reflex] ->
        refusal(candidate, "unsupported Knowledge Hook promotion class", %{class: candidate.class})

      true ->
        :ok
    end
  end

  defp evidence_identity(evidence) do
    invalid =
      Enum.reject(evidence, fn
        %Evidence{receipt_sha256: receipt} when is_binary(receipt) and receipt != "" -> true
        _ -> false
      end)

    if invalid == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hook_promotion,
         "promotion evidence requires stable receipt identities"
       )}
    end
  end

  defp evidence_envelope(candidate, evidence) do
    mismatches =
      Enum.reject(evidence, fn item ->
        item.subject == candidate.subject and
          item.scope == candidate.scope and
          item.policy_sha256 == candidate.policy_sha256 and
          item.verifier_sha256 == candidate.verifier_sha256
      end)

    if mismatches == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         candidate.hook_spec_sha256,
         "promotion evidence escapes the candidate subject/scope/policy/verifier envelope",
         %{mismatch_count: length(mismatches)}
       )}
    end
  end

  defp evidence_quality(evidence) do
    invalid =
      Enum.reject(evidence, fn item ->
        item.observed? and item.standing == :ALIVE and item.postcondition_verified? and item.replay_verified?
      end)

    if invalid == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hook_promotion,
         "promotion requires observed ALIVE evidence with verified postcondition and replay",
         %{invalid_receipts: Enum.map(invalid, & &1.receipt_sha256)}
       )}
    end
  end

  defp minimum_evidence(evidence, minimum_positive, minimum_falsifiers) do
    positives = Enum.count(evidence, & &1.positive?)
    falsifiers = Enum.count(evidence, & &1.falsifier?)

    cond do
      positives < minimum_positive ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_promotion,
           "insufficient positive evidence for deterministic promotion",
           %{required: minimum_positive, observed: positives}
         )}

      falsifiers < minimum_falsifiers ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_promotion,
           "promotion requires explicit falsifier evidence",
           %{required: minimum_falsifiers, observed: falsifiers}
         )}

      true ->
        :ok
    end
  end

  defp refusal(candidate, detail, evidence \\ %{}) do
    {:error, Refusal.new(:REFUSED_UNPROVEN_EQUIVALENCE, candidate.hook_spec_sha256, detail, evidence)}
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHookPromotionTest do
  use ExUnit.Case, async: true

  alias AshR2RML.KnowledgeHook.Promotion
  alias AshR2RML.KnowledgeHook.Promotion.{Candidate, Evidence}

  defp candidate(overrides \\ %{}) do
    struct!(Candidate,
      Map.merge(
        %{
          hook_spec_sha256: String.duplicate("1", 64),
          subject: "customer:42",
          scope: "customer-readiness",
          policy_sha256: String.duplicate("2", 64),
          verifier_sha256: String.duplicate("3", 64),
          class: :construct
        },
        overrides
      )
    )
  end

  defp evidence(receipt, overrides) do
    struct!(Evidence,
      Map.merge(
        %{
          receipt_sha256: receipt,
          subject: "customer:42",
          scope: "customer-readiness",
          policy_sha256: String.duplicate("2", 64),
          verifier_sha256: String.duplicate("3", 64),
          standing: :ALIVE,
          observed?: true,
          postcondition_verified?: true,
          replay_verified?: true
        },
        overrides
      )
    )
  end

  test "sufficient evidence produces a powerless promotion candidate" do
    observations = [
      evidence(String.duplicate("a", 64), %{positive?: true}),
      evidence(String.duplicate("b", 64), %{positive?: true}),
      evidence(String.duplicate("c", 64), %{falsifier?: true})
    ]

    assert {:ok, result} = Promotion.evaluate(candidate(), observations)
    assert result.standing == :promotion_candidate
    assert result.authority == :UNAUTHORIZED
    assert result.receipt.authority == :UNAUTHORIZED
    assert result.receipt.blocked == [:actuation_authority]
    assert result.brce_request.authority == :UNAUTHORIZED
    refute result.brce_request.do_authority
    assert result.brce_request.requires_actuation_receipt?
  end

  test "promotion refuses direct or embedded authority" do
    observations = [
      evidence(String.duplicate("a", 64), %{positive?: true}),
      evidence(String.duplicate("b", 64), %{positive?: true}),
      evidence(String.duplicate("c", 64), %{falsifier?: true})
    ]

    assert {:error, refusal} = Promotion.evaluate(candidate(%{direct_do?: true}), observations)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE

    assert {:error, refusal} = Promotion.evaluate(candidate(%{embedded_authority?: true}), observations)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
  end

  test "reflex class requires compensation" do
    observations = [
      evidence(String.duplicate("a", 64), %{positive?: true}),
      evidence(String.duplicate("b", 64), %{positive?: true}),
      evidence(String.duplicate("c", 64), %{falsifier?: true})
    ]

    assert {:error, refusal} = Promotion.evaluate(candidate(%{class: :reflex}), observations)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE

    assert {:ok, result} =
             Promotion.evaluate(candidate(%{class: :reflex, compensation: %{target: "cognition://fallback"}}), observations)

    assert result.authority == :UNAUTHORIZED
  end

  test "promotion requires explicit positive, falsifier, replay, and postcondition evidence" do
    only_positive = [
      evidence(String.duplicate("a", 64), %{positive?: true}),
      evidence(String.duplicate("b", 64), %{positive?: true})
    ]

    assert {:error, _} = Promotion.evaluate(candidate(), only_positive)

    broken = [
      evidence(String.duplicate("a", 64), %{positive?: true}),
      evidence(String.duplicate("b", 64), %{positive?: true, replay_verified?: false}),
      evidence(String.duplicate("c", 64), %{falsifier?: true})
    ]

    assert {:error, refusal} = Promotion.evaluate(candidate(), broken)
    assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
  end

  test "cognition elimination rate is bounded" do
    assert Promotion.cognition_elimination_rate(100, 25) == 0.75
    assert Promotion.cognition_elimination_rate(100, 0) == 1.0
    assert Promotion.cognition_elimination_rate(100, 120) == 0.0
    assert Promotion.cognition_elimination_rate(0, 0) == 1.0
  end
end

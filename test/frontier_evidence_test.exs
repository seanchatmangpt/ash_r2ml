# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidenceTest do
  use ExUnit.Case, async: true

  test "projects observed hook evidence without adding DO authority" do
    observations = [
      %{
        receipt_sha256: "obs-1",
        source: :ash_notification,
        standing: :observed_ash_primitive,
        authority: :UNAUTHORIZED
      }
    ]

    evaluations = [
      %{
        evaluation_receipt_sha256: "eval-1",
        matched?: true,
        intent: %{authority: :UNAUTHORIZED, standing: :constructed_not_actuated}
      }
    ]

    fragment =
      AshR2RML.FrontierEvidence.from_knowledge_hooks(observations, evaluations,
        producer_head: "77652b894d3c3ec9b08fdda2d796c7e7b9083b51"
      )

    assert fragment.schema == "frontier-evidence/v1"
    assert fragment.producer == "ash_r2rml"
    assert fragment.authority_ceiling == "CONSTRUCT"
    assert fragment.artifact_hash =~ ~r/^sha256:[0-9a-f]{64}$/
    assert "callbacks" in fragment.refused
    assert "actuation_authority" in fragment.refused
  end

  test "projection is deterministic for identical observations" do
    opts = [producer_head: "head"]
    observations = [%{receipt_sha256: "same"}]
    evaluations = [%{evaluation_receipt_sha256: "same"}]

    first = AshR2RML.FrontierEvidence.from_knowledge_hooks(observations, evaluations, opts)
    second = AshR2RML.FrontierEvidence.from_knowledge_hooks(observations, evaluations, opts)

    assert first.artifact_hash == second.artifact_hash
  end
end

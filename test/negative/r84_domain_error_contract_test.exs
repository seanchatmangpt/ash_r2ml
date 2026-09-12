# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Negative.R84DomainErrorContractTest do
  @moduledoc """
  Consumer court for ggen-marketplace R84 `ash-reactor-domain-error-contract-pack`.

  The canonical producer requires typed domain refusals to survive the Reactor
  boundary instead of being collapsed into a generic execution envelope.
  """

  use ExUnit.Case, async: true

  @producer "seanchatmangpt/ggen-marketplace@6b7fb4af7b4ef3a6330ad61ca833b98902300332"
  @pack "packs/ash-reactor-domain-error-contract-pack"

  defmodule BrokenPipelineResource do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets

    attributes do
      uuid_primary_key :id
    end
  end

  test "R84 producer identity is exact and pack-owned" do
    assert @producer =~ ~r/@[0-9a-f]{40}$/
    assert @pack == "packs/ash-reactor-domain-error-contract-pack"
  end

  test "compile step preserves the typed AshR2RML refusal" do
    assert {:error, %AshR2RML.Refusal{} = refusal} =
             AshR2RML.Reactor.Steps.CompileResources.run(
               %{resources: [BrokenPipelineResource]},
               %{},
               []
             )

    assert is_atom(refusal.code)
    refute refusal.code in [nil, :unknown]
  end

  test "typed refusal is fail-closed and non-retryable at compensation" do
    {:error, %AshR2RML.Refusal{} = refusal} =
      AshR2RML.Reactor.Steps.CompileResources.run(
        %{resources: [BrokenPipelineResource]},
        %{},
        []
      )

    assert :ok =
             AshR2RML.Reactor.Steps.CompileResources.compensate(
               refusal,
               %{},
               %{},
               []
             )
  end
end

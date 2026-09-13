# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Target do
  @moduledoc """
  Typed inert projection of a Knowledge Hook intent toward downstream Ash
  machinery. A target names possible downstream work; it never invokes it.

  This module intentionally has no dependency on AshOban. `:oban` targets are
  data contracts only, preserving the same authority boundary as Reactor, Ash
  actions, and state-machine transition targets.
  """

  alias AshR2RML.KnowledgeHook.Intent
  alias AshR2RML.{Compiler, Refusal}

  @enforce_keys [:kind, :target, :target_sha256]
  defstruct [
    :kind,
    :target,
    :target_sha256,
    payload: %{},
    metadata: %{},
    authority: :UNAUTHORIZED,
    standing: :constructed_not_actuated,
    requires_actuation_receipt?: true
  ]

  @type kind :: :reactor | :ash_action | :state_transition | :oban | :workflow | :pipeline | :opaque_target
  @type t :: %__MODULE__{
          kind: kind(),
          target: term(),
          target_sha256: String.t(),
          payload: map(),
          metadata: map(),
          authority: :UNAUTHORIZED,
          standing: :constructed_not_actuated,
          requires_actuation_receipt?: true
        }

  @doc "Construct an inert Reactor target."
  @spec reactor(term(), map()) :: {:ok, t()} | {:error, Refusal.t()}
  def reactor(target, input \\ %{}), do: new(:reactor, stable_name(target), input)

  @doc "Construct an inert Ash action target."
  @spec ash_action(term(), term(), map()) :: {:ok, t()} | {:error, Refusal.t()}
  def ash_action(resource, action, input \\ %{}) do
    new(:ash_action, %{resource: stable_name(resource), action: stable_name(action)}, input)
  end

  @doc "Construct an inert AshStateMachine transition target."
  @spec state_transition(term(), term(), map()) :: {:ok, t()} | {:error, Refusal.t()}
  def state_transition(resource, transition, input \\ %{}) do
    new(:state_transition, %{resource: stable_name(resource), transition: stable_name(transition)}, input)
  end

  @doc "Construct an inert Oban/AshOban-compatible job description without scheduling it."
  @spec oban(term(), map(), term()) :: {:ok, t()} | {:error, Refusal.t()}
  def oban(worker, args \\ %{}, schedule \\ :immediate) do
    new(:oban, stable_name(worker), args, %{schedule: schedule})
  end

  @doc "Normalize an already-constructed Knowledge Hook intent to a typed inert target."
  @spec from_intent(map()) :: {:ok, t()} | {:error, Refusal.t()}
  def from_intent(%Intent{} = intent) do
    with :ok <- require_unauthorized(intent),
         {:ok, target} <- new(normalize_kind(intent.kind), intent.target, intent.payload || %{}) do
      {:ok,
       %{
         target
         | metadata: %{
             hook_id: intent.hook_id,
             trigger_type: intent.trigger_type,
             evaluation_receipt_sha256: intent.evaluation_receipt_sha256
           },
           authority: :UNAUTHORIZED,
           standing: :constructed_not_actuated,
           requires_actuation_receipt?: true
       }}
    end
  end

  @doc "Stable serializable projection."
  @spec projection(t()) :: map()
  def projection(%__MODULE__{} = target) do
    %{
      kind: target.kind,
      target: target.target,
      payload: target.payload,
      metadata: target.metadata,
      target_sha256: target.target_sha256,
      authority: :UNAUTHORIZED,
      standing: :constructed_not_actuated,
      requires_actuation_receipt?: true
    }
  end

  defp new(kind, target, payload, metadata \\ %{}) do
    normalized_kind = normalize_kind(kind)

    cond do
      normalized_kind == :unsupported ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_target,
           "unsupported Knowledge Hook downstream target kind",
           %{kind: kind}
         )}

      is_nil(target) ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_target,
           "Knowledge Hook downstream target must have stable identity"
         )}

      not inert?(target) or not inert?(payload) or not inert?(metadata) ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_target,
           "Knowledge Hook downstream target must contain inert data only"
         )}

      true ->
        core = %{kind: normalized_kind, target: target, payload: payload, metadata: metadata}

        {:ok,
         %__MODULE__{
           kind: normalized_kind,
           target: target,
           payload: payload,
           metadata: metadata,
           target_sha256: Compiler.sha256(core)
         }}
    end
  end

  defp require_unauthorized(%Intent{authority: :UNAUTHORIZED, requires_actuation_receipt?: true}), do: :ok

  defp require_unauthorized(intent) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       intent.hook_id,
       "Knowledge Hook intent attempted to cross the authority conservation boundary",
       %{authority: intent.authority, requires_actuation_receipt?: intent.requires_actuation_receipt?}
     )}
  end

  defp normalize_kind(kind)
       when kind in [:reactor, :ash_action, :state_transition, :oban, :workflow, :pipeline, :opaque_target],
       do: kind

  defp normalize_kind("reactor"), do: :reactor
  defp normalize_kind("ash_action"), do: :ash_action
  defp normalize_kind("state_transition"), do: :state_transition
  defp normalize_kind("oban"), do: :oban
  defp normalize_kind("workflow"), do: :workflow
  defp normalize_kind("pipeline"), do: :pipeline
  defp normalize_kind("opaque_target"), do: :opaque_target
  defp normalize_kind(_), do: :unsupported

  defp stable_name(value) when is_atom(value), do: Atom.to_string(value)
  defp stable_name(value) when is_binary(value), do: value
  defp stable_name(value), do: inspect(value)

  defp inert?(value) when is_function(value) or is_pid(value) or is_port(value) or is_reference(value), do: false
  defp inert?(%_{}), do: false
  defp inert?(map) when is_map(map), do: Enum.all?(map, fn {k, v} -> inert?(k) and inert?(v) end)
  defp inert?(list) when is_list(list), do: Enum.all?(list, &inert?/1)
  defp inert?(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.all?(&inert?/1)
  defp inert?(_), do: true
end

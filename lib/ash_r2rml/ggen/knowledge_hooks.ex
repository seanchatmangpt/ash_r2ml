# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen.KnowledgeHooks do
  @moduledoc """
  Deterministic ggen path/content projection for admitted knowledge-hook plans.

  This module manufactures files only. It does not register hooks, schedule
  timers, execute pipelines, invoke actions, or grant downstream DO authority.
  """

  alias AshR2RML.KnowledgeHook.Plan

  @doc "Compile normalized hook definitions or an existing plan into a ggen bundle."
  @spec compile(Plan.t() | [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def compile(plan_or_definitions, opts \\ [])

  def compile(%Plan{} = plan, _opts), do: bundle(plan)

  def compile(definitions, opts) when is_list(definitions) do
    with {:ok, plan} <- AshR2RML.KnowledgeHooks.admit(definitions, opts) do
      bundle(plan)
    end
  end

  @doc "Parse GitVan/KNHK Turtle, admit the hooks, and manufacture a ggen bundle."
  @spec compile_turtle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_turtle(turtle, opts \\ []) do
    with {:ok, plan} <- AshR2RML.KnowledgeHooks.from_turtle(turtle, opts) do
      bundle(plan)
    end
  end

  defp bundle(plan) do
    projection = AshR2RML.KnowledgeHooks.projection(plan)

    receipt = %{
      status: :PARTIAL_ALIVE,
      standing: :construct_only,
      authority: :UNAUTHORIZED,
      plan_sha256: plan.plan_sha256,
      hook_count: length(plan.hooks),
      generated: ["generated/knowledge-hooks/plan.json"],
      blocked: [:hook_actuation_authority]
    }

    with {:ok, plan_json} <- encode_json(projection),
         {:ok, receipt_json} <- encode_json(receipt) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         authority: :UNAUTHORIZED,
         knowledge_hook_plan_sha256: plan.plan_sha256,
         plan: plan,
         files: %{
           "generated/knowledge-hooks/plan.json" => plan_json <> "\n",
           "receipts/knowledge-hooks-compilation.json" => receipt_json <> "\n"
         }
       }}
    end
  end

  defp encode_json(value), do: value |> json_term() |> Jason.encode(pretty: true)
  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()

  defp json_term(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)
  end

  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value) when is_binary(value) or is_number(value), do: value
  defp json_term(value), do: inspect(value)

  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
# SPDX-License-Identifier: MIT

defmodule AshR2RML.FrontierEvidence do
  @moduledoc """
  Content-addressed FrontierEvidence v1 projection for observed knowledge-hook data.

  Inputs must already be observation/evaluation receipts. This module performs no
  notifier registration, hook registration, callback execution, scheduling, file
  writes, or downstream actuation. It preserves ash_r2rml's OBSERVE/SELECT/CONSTRUCT
  authority ceiling while making the evidence portable to a downstream admission
  court such as XaaS.
  """

  @schema "frontier-evidence/v1"
  @producer "ash_r2rml"
  @authority_ceiling "CONSTRUCT"

  @spec from_knowledge_hooks(list(), list(), keyword()) :: map()
  def from_knowledge_hooks(observations, evaluations, opts \\ [])
      when is_list(observations) and is_list(evaluations) do
    producer_head = Keyword.fetch!(opts, :producer_head)
    standing = Keyword.get(opts, :standing, "PARTIAL_ALIVE")

    evidence = %{
      observations: Enum.map(observations, &canonical_term/1),
      evaluations: Enum.map(evaluations, &canonical_term/1)
    }

    body = %{
      schema: @schema,
      producer: @producer,
      producer_head: producer_head,
      standing: standing,
      authority_ceiling: @authority_ceiling,
      evidence: evidence,
      refused: [
        "callbacks",
        "timers",
        "hook_registration",
        "unobserved_external_triggers",
        "actuation_authority"
      ]
    }

    Map.put(body, :artifact_hash, fingerprint(body))
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

  defp canonical_term(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp canonical_term(other), do: other
end

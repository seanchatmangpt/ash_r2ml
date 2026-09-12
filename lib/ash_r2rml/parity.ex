# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.ParityReceipt do
  @moduledoc "Receipt for an observed result-equivalence comparison."

  defstruct [
    :kind,
    :subject,
    :left_system,
    :right_system,
    :left_query_sha256,
    :right_query_sha256,
    :left_result_sha256,
    :right_result_sha256,
    :fixture_sha256,
    :mapping_sha256,
    :verified?,
    :receipt_sha256,
    left_count: 0,
    right_count: 0,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          kind: :sparql_sql,
          subject: term(),
          left_system: atom() | String.t(),
          right_system: atom() | String.t(),
          left_query_sha256: String.t() | nil,
          right_query_sha256: String.t() | nil,
          left_result_sha256: String.t(),
          right_result_sha256: String.t(),
          fixture_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          verified?: boolean(),
          receipt_sha256: String.t(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer(),
          metadata: map()
        }
end

defmodule AshR2RML.Parity do
  @moduledoc """
  Deterministic semantic-result comparator for side-by-side cutover evidence.

  Query execution is intentionally outside this module. Callers execute the
  admitted SQL/SPARQL queries, then pass their observed rows here. The
  comparator normalizes result multisets and emits a stable receipt that can be
  attached to `AshR2RML.CompilationReceipt`.
  """

  alias AshR2RML.ParityReceipt

  @spec compare(:sparql_sql, term(), list(), list(), map()) :: ParityReceipt.t()
  def compare(kind, subject, left_rows, right_rows, metadata \\ %{})
      when kind == :sparql_sql and is_list(left_rows) and is_list(right_rows) do
    left = normalize_multiset(left_rows)
    right = normalize_multiset(right_rows)
    left_hash = sha256(left)
    right_hash = sha256(right)

    receipt = %ParityReceipt{
      kind: kind,
      subject: subject,
      left_system: get(metadata, :left_system) || default_left(kind),
      right_system: get(metadata, :right_system) || default_right(kind),
      left_query_sha256: query_hash(get(metadata, :left_query)),
      right_query_sha256: query_hash(get(metadata, :right_query)),
      left_result_sha256: left_hash,
      right_result_sha256: right_hash,
      fixture_sha256: get(metadata, :fixture_sha256),
      mapping_sha256: get(metadata, :mapping_sha256),
      verified?: left == right,
      left_count: length(left_rows),
      right_count: length(right_rows),
      metadata: Map.drop(metadata, [:left_query, :right_query, "left_query", "right_query"])
    }

    %{receipt | receipt_sha256: sha256(canonical(Map.from_struct(receipt)))}
  end

  @doc "Normalize an unordered result multiset while preserving duplicate cardinality."
  def normalize_multiset(rows) do
    rows
    |> Enum.map(&canonical/1)
    |> Enum.sort_by(&:erlang.term_to_binary(&1, [:deterministic]))
  end

  defp canonical(%Decimal{} = decimal) do
    decimal
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp canonical(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp canonical(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp canonical(%Date{} = date), do: Date.to_iso8601(date)
  defp canonical(%RDF.IRI{value: value}), do: canonical(to_string(value))
  defp canonical(%RDF.Literal{} = literal), do: literal |> RDF.Literal.value() |> canonical()
  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Enum.map(fn {key, value} -> {normalize_key(key), canonical(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(value) when is_atom(value) and value not in [true, false, nil], do: Atom.to_string(value)
  defp canonical(value) when is_integer(value), do: Integer.to_string(value)
  defp canonical(value) when is_float(value), do: Float.to_string(value)
  defp canonical(value) when is_boolean(value), do: to_string(value)

  defp canonical(value) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      String.starts_with?(trimmed, "<") and String.ends_with?(trimmed, ">") and byte_size(trimmed) >= 2 ->
        trimmed |> String.slice(1..-2//1)

      match?({_, ""}, Decimal.parse(trimmed)) ->
        case Decimal.parse(trimmed) do
          {%Decimal{} = dec, ""} ->
            dec
            |> Decimal.normalize()
            |> Decimal.to_string(:normal)

          _ ->
            trimmed
        end

      true ->
        trimmed
    end
  end

  defp canonical(value), do: value

  defp normalize_key(%{name: name}), do: to_string(name)
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key) |> String.trim_leading("?")
  defp normalize_key(key) when is_binary(key), do: String.trim_leading(key, "?")
  defp normalize_key(other), do: other |> to_string() |> String.trim_leading("?")

  defp query_hash(nil), do: nil
  defp query_hash(query), do: sha256(to_string(query))

  defp default_left(:sparql_sql), do: :sparql
  defp default_right(:sparql_sql), do: :sql

  defp get(map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end

  defp sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  defp sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end

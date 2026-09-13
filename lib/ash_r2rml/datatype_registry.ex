# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Datatype.Registry do
  @moduledoc """
  Loss-aware built-in and custom datatype correspondence.

  Unknown Ash types are never stringified implicitly. Custom semantic types are
  admitted as RDF datatypes only when their `AshR2RML.Type` contract is
  explicitly `:literal`; IRI, concept, value-object, and resource semantics must
  take their own R2RML term-map/resource path.
  """

  alias AshR2RML.Mapping.Datatype
  alias AshR2RML.Refusal

  @xsd "http://www.w3.org/2001/XMLSchema#"
  @ogc_geo "http://www.opengis.net/ont/geosparql#"

  @builtins %{
    string: {@xsd <> "string", :text},
    boolean: {@xsd <> "boolean", :boolean},
    integer: {@xsd <> "integer", :bigint},
    float: {@xsd <> "double", :float},
    decimal: {@xsd <> "decimal", :decimal},
    date: {@xsd <> "date", :date},
    time: {@xsd <> "time", :time},
    utc_datetime: {@xsd <> "dateTime", :utc_datetime},
    utc_datetime_usec: {@xsd <> "dateTime", :utc_datetime_usec},
    naive_datetime: {@xsd <> "dateTime", :naive_datetime},
    naive_datetime_usec: {@xsd <> "dateTime", :naive_datetime_usec},
    uuid: {@xsd <> "string", :uuid},
    ci_string: {@xsd <> "string", :citext},
    atom: {@xsd <> "string", :text},
    geo_wkt: {@ogc_geo <> "wktLiteral", :geometry},
    vector: {@xsd <> "string", :vector},
    array: {@xsd <> "string", :array},
    duration: {@xsd <> "duration", :duration}
  }

  @ash_type_modules %{
    "Elixir.Ash.Type.String" => :string,
    "Elixir.Ash.Type.Boolean" => :boolean,
    "Elixir.Ash.Type.Integer" => :integer,
    "Elixir.Ash.Type.Float" => :float,
    "Elixir.Ash.Type.Decimal" => :decimal,
    "Elixir.Ash.Type.Date" => :date,
    "Elixir.Ash.Type.Time" => :time,
    "Elixir.Ash.Type.UtcDatetime" => :utc_datetime,
    "Elixir.Ash.Type.UtcDatetimeUsec" => :utc_datetime_usec,
    "Elixir.Ash.Type.NaiveDatetime" => :naive_datetime,
    "Elixir.Ash.Type.NaiveDatetimeUsec" => :naive_datetime_usec,
    "Elixir.Ash.Type.UUID" => :uuid,
    "Elixir.Ash.Type.CiString" => :ci_string,
    "Elixir.Ash.Type.Atom" => :atom,
    "Elixir.AshGeo.Geometry" => :geo_wkt,
    "Elixir.AshGeo.Point" => :geo_wkt,
    "Elixir.Ash.Type.Vector" => :vector,
    "Elixir.Ash.Type.Duration" => :duration
  }

  @spec resolve(term(), String.t() | nil, term() | nil) :: {:ok, Datatype.t()} | {:error, Refusal.t()}
  def resolve(ash_type, rdf_override \\ nil, storage_override \\ nil) do
    normalized = normalize_ash_type(ash_type)
    semantic_contract = semantic_contract(ash_type)

    cond do
      is_binary(rdf_override) and absolute_iri?(rdf_override) ->
        {:ok,
         %Datatype{
           ash_type: ash_type,
           rdf_datatype: rdf_override,
           storage_type: storage_override || builtin_storage(normalized)
         }}

      is_binary(rdf_override) ->
        {:error,
         Refusal.new(:REFUSED_UNMAPPED_DATATYPE, ash_type, "explicit RDF datatype must be an absolute IRI", %{
           rdf_datatype: rdf_override
         })}

      semantic_literal?(semantic_contract) ->
        {:literal, rdf_datatype} = semantic_contract

        {:ok,
         %Datatype{
           ash_type: ash_type,
           rdf_datatype: rdf_datatype,
           storage_type: storage_override || semantic_storage(ash_type) || :text
         }}

      match?({:non_literal, _}, semantic_contract) ->
        {:non_literal, semantic_kind} = semantic_contract

        {:error,
         Refusal.new(
           :REFUSED_NON_LITERAL_DATATYPE,
           ash_type,
           "non-literal semantic Ash type cannot be compiled as an RDF datatype",
           %{semantic_kind: semantic_kind}
         )}

      legacy_literal_type?(ash_type) ->
        {:ok,
         %Datatype{ash_type: ash_type, rdf_datatype: ash_type.xsd_datatype(), storage_type: storage_override || :text}}

      enum_type?(ash_type) ->
        {:ok, %Datatype{ash_type: ash_type, rdf_datatype: @xsd <> "string", storage_type: storage_override || :text}}

      Map.has_key?(@builtins, normalized) ->
        {rdf_datatype, storage} = Map.fetch!(@builtins, normalized)
        {:ok, %Datatype{ash_type: ash_type, rdf_datatype: rdf_datatype, storage_type: storage_override || storage}}

      true ->
        {:error,
         Refusal.new(
           :UNSUPPORTED_ASH_TYPE,
           ash_type,
           "Ash type has no admitted RDF datatype contract; supply an explicit mapping or implement a literal AshR2RML.Type",
           %{normalized_type: normalized}
         )}
    end
  end

  @spec supported?(term()) :: boolean()
  def supported?(ash_type) do
    case semantic_contract(ash_type) do
      {:literal, datatype} when is_binary(datatype) ->
        true

      {:non_literal, _} ->
        false

      _ ->
        legacy_literal_type?(ash_type) or enum_type?(ash_type) or Map.has_key?(@builtins, normalize_ash_type(ash_type))
    end
  end

  @spec builtin_contracts() :: map()
  def builtin_contracts, do: @builtins

  defp semantic_contract(ash_type) when is_atom(ash_type) do
    case AshR2RML.Type.contract(ash_type) do
      {:ok, %{semantic_kind: :literal, datatype_iri: datatype}} -> {:literal, datatype}
      {:ok, %{semantic_kind: kind}} -> {:non_literal, kind}
      :error -> :none
    end
  end

  defp semantic_contract(_), do: :none

  defp semantic_literal?({:literal, datatype}), do: is_binary(datatype) and absolute_iri?(datatype)
  defp semantic_literal?(_), do: false

  defp semantic_storage(ash_type) do
    if is_atom(ash_type) and Code.ensure_loaded?(ash_type) and function_exported?(ash_type, :storage_type, 1) do
      try do
        ash_type.storage_type([])
      rescue
        _ -> nil
      end
    end
  end

  defp legacy_literal_type?(ash_type) do
    is_atom(ash_type) and Code.ensure_loaded?(ash_type) and function_exported?(ash_type, :xsd_datatype, 0) and
      is_binary(ash_type.xsd_datatype()) and absolute_iri?(ash_type.xsd_datatype())
  end

  defp enum_type?(ash_type) do
    is_atom(ash_type) and Code.ensure_loaded?(ash_type) and function_exported?(ash_type, :values, 0) and
      (Spark.implements_behaviour?(ash_type, Ash.Type.Enum) or function_exported?(ash_type, :storage_type, 0))
  end

  defp builtin_storage(normalized) do
    case Map.get(@builtins, normalized) do
      {_rdf, storage} -> storage
      nil -> nil
    end
  end

  defp normalize_ash_type(type) when is_atom(type) do
    if Map.has_key?(@builtins, type), do: type, else: Map.get(@ash_type_modules, Atom.to_string(type), type)
  end

  defp normalize_ash_type(type), do: type

  defp absolute_iri?(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticTypes do
  @moduledoc """
  Pure SELECT/CONSTRUCT compiler for public-ontology semantic value spaces.

  Inputs may be public IRIs, a list of IRI/profile entries, or a JSON-compatible
  map containing `types`. All paths converge on `AshR2RML.SemanticType.Plan`.

  This module performs no filesystem writes, migrations, network access, or
  production actuation.
  """

  alias AshR2RML.{Refusal, SemanticType}
  alias AshR2RML.SemanticType.{Diff, Plan}

  @default_providers [
    AshR2RML.SemanticTypes.XSD,
    AshR2RML.SemanticTypes.RDF,
    AshR2RML.SemanticTypes.SKOS,
    AshR2RML.SemanticTypes.QUDT,
    AshR2RML.SemanticTypes.GeoSPARQL,
    AshR2RML.SemanticTypes.OWLTime
  ]

  @representation_atoms [:builtin, :new_type, :custom_type, :registry, :composite, :embedded, :jsonb, :resource]

  @spec providers(keyword()) :: [module()]
  def providers(opts \\ []) do
    Keyword.get(opts, :providers, Application.get_env(:ash_r2rml, :semantic_type_providers, @default_providers))
  end

  @spec resolve(String.t(), keyword()) :: {:ok, SemanticType.t()} | {:error, Refusal.t()}
  def resolve(iri, opts \\ [])

  def resolve(iri, opts) when is_binary(iri) do
    if SemanticType.absolute_iri?(iri) do
      providers(opts)
      |> Enum.reduce_while(:unknown, fn provider, _acc ->
        case provider.resolve(iri, opts) do
          :unknown -> {:cont, :unknown}
          {:ok, %SemanticType{} = type} -> {:halt, apply_overrides(type, opts)}
          {:error, error} -> {:halt, {:error, error}}
        end
      end)
      |> case do
        :unknown ->
          {:error,
           Refusal.new(
             :UNSUPPORTED_SEMANTIC_TYPE,
             iri,
             "no configured public-ontology provider admits this semantic type",
             %{
               providers: Enum.map(providers(opts), & &1.id())
             }
           )}

        result ->
          result
      end
    else
      {:error, Refusal.new(:REFUSED_SEMANTIC_TYPE_INVALID, iri, "semantic type identifier must be an absolute IRI")}
    end
  end

  def resolve(other, _opts),
    do: {:error, Refusal.new(:REFUSED_SEMANTIC_TYPE_INVALID, other, "semantic type identifier must be an IRI string")}

  @doc "Construct an explicit RDF IRI semantic type without inventing an ontology class."
  @spec iri_type(keyword()) :: {:ok, SemanticType.t()} | {:error, Refusal.t()}
  def iri_type(opts \\ []) do
    SemanticType.new(
      name: Keyword.get(opts, :name, :iri),
      provider: :rdf,
      source_iri: Keyword.get(opts, :source_iri, "urn:ash-r2rml:semantic-type:iri"),
      semantic_kind: :iri,
      ash_type: AshR2RML.Types.IRI,
      storage_type: :string,
      postgres_type: "TEXT",
      constraints: Keyword.take(opts, [:prefix]),
      shacl_constraints: [node_kind: :iri],
      selected_representation: Keyword.get(opts, :selected_representation),
      provenance: %{authority: :rdf_term_model}
    )
  end

  @spec compile(term(), keyword()) :: {:ok, [SemanticType.t()]} | {:error, [Refusal.t()]}
  def compile(source, opts \\ [])
  def compile(%Plan{types: types}, _opts), do: {:ok, types}
  def compile(%SemanticType{} = type, _opts), do: {:ok, [type]}

  def compile(source, opts) when is_binary(source) do
    trimmed = String.trim(source)

    cond do
      String.starts_with?(trimmed, "{") or String.starts_with?(trimmed, "[") ->
        case Jason.decode(trimmed) do
          {:ok, decoded} -> compile(decoded, opts)
          {:error, error} -> {:error, [Refusal.new(:REFUSED_SEMANTIC_PROFILE_INVALID, :json, inspect(error))]}
        end

      SemanticType.absolute_iri?(trimmed) ->
        case resolve(trimmed, opts) do
          {:ok, type} -> {:ok, [type]}
          {:error, refusal} -> {:error, [refusal]}
        end

      true ->
        {:error,
         [
           Refusal.new(
             :REFUSED_SEMANTIC_PROFILE_INVALID,
             :source,
             "binary semantic source must be JSON or an absolute IRI"
           )
         ]}
    end
  end

  def compile(%{} = source, opts) do
    entries = get(source, :types)

    cond do
      is_list(entries) -> compile(entries, opts)
      entry?(source) -> compile([source], opts)
      true -> {:error, [Refusal.new(:REFUSED_SEMANTIC_PROFILE_INVALID, :types, "profile must contain a types list")]}
    end
  end

  def compile(entries, opts) when is_list(entries) do
    entries
    |> Enum.reduce({[], []}, fn entry, {types, refusals} ->
      case compile_entry(entry, opts) do
        {:ok, type} -> {[type | types], refusals}
        {:error, refusal} -> {types, [refusal | refusals]}
      end
    end)
    |> case do
      {types, []} -> {:ok, types |> Enum.reverse() |> Enum.sort_by(&type_key/1)}
      {_types, refusals} -> {:error, Enum.reverse(refusals)}
    end
  end

  def compile(other, _opts),
    do:
      {:error,
       [
         Refusal.new(
           :REFUSED_SEMANTIC_PROFILE_INVALID,
           other,
           "semantic source must be an IRI, profile map, list, or JSON document"
         )
       ]}

  @spec plan(term(), keyword()) :: {:ok, Plan.t()} | {:error, [Refusal.t()]}
  def plan(source, opts \\ []) do
    with {:ok, types} <- compile(source, opts),
         :ok <- verify(types) do
      provider_ids = types |> Enum.map(& &1.provider) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()
      id = plan_hash(types, provider_ids)
      {:ok, %Plan{id: id, types: types, providers: provider_ids, refusals: [], status: :PARTIAL_ALIVE}}
    else
      {:error, refusals} when is_list(refusals) -> {:error, refusals}
    end
  end

  @spec verify(Plan.t() | [SemanticType.t()]) :: :ok | {:error, [Refusal.t()]}
  def verify(%Plan{types: types}), do: verify(types)

  def verify(types) when is_list(types) do
    refusals = Enum.flat_map(types, &verify_type/1)
    if refusals == [], do: :ok, else: {:error, refusals}
  end

  @spec manifest(Plan.t()) :: map()
  def manifest(%Plan{} = plan) do
    %{
      schema: "https://ash-r2rml.dev/schema/semantic-type-plan/v1",
      plan_id: plan.id,
      status: plan.status,
      providers: plan.providers,
      types: Enum.map(plan.types, &manifest_type/1)
    }
  end

  @spec manifest_json(Plan.t()) :: {:ok, String.t()} | {:error, Jason.EncodeError.t()}
  def manifest_json(%Plan{} = plan), do: Jason.encode(manifest(plan), pretty: true)

  @spec diff(Plan.t() | map(), Plan.t() | map()) :: Diff.t()
  def diff(expected, observed) do
    expected_map = normalize_manifest(expected)
    observed_map = normalize_manifest(observed)
    expected_types = index_manifest_types(expected_map)
    observed_types = index_manifest_types(observed_map)

    missing = Map.keys(expected_types) |> Enum.reject(&Map.has_key?(observed_types, &1)) |> Enum.sort()
    extra = Map.keys(observed_types) |> Enum.reject(&Map.has_key?(expected_types, &1)) |> Enum.sort()

    changed =
      Map.keys(expected_types)
      |> Enum.filter(&Map.has_key?(observed_types, &1))
      |> Enum.flat_map(fn key ->
        expected_type = Map.fetch!(expected_types, key)
        observed_type = Map.fetch!(observed_types, key)

        semantic_differences(expected_type, observed_type)
        |> Enum.map(fn field ->
          %{
            kind: :changed,
            semantic_type: key,
            field: field,
            expected: get(expected_type, field),
            observed: get(observed_type, field)
          }
        end)
      end)

    changes =
      Enum.map(missing, &%{kind: :missing_observed, semantic_type: &1}) ++
        Enum.map(extra, &%{kind: :extra_observed, semantic_type: &1}) ++ changed

    status =
      cond do
        changes == [] -> :ALIGNED
        changed != [] -> :LOSSY
        missing != [] and extra != [] -> :AMBIGUOUS
        missing != [] -> :ONTOLOGY_AHEAD
        extra != [] -> :ASH_AHEAD
        true -> :REFUSED
      end

    %Diff{
      status: status,
      changes: changes,
      expected_id: get(expected_map, :plan_id),
      observed_id: get(observed_map, :plan_id)
    }
  end

  @spec round_trip(SemanticType.t(), term()) :: {:ok, map()} | {:error, Refusal.t()}
  def round_trip(%SemanticType{} = type, value) do
    with {:ok, casted} <- normalize_result(Ash.Type.cast_input(type.ash_type, value, type.constraints)),
         {:ok, native} <- normalize_result(Ash.Type.dump_to_native(type.ash_type, casted, type.constraints)),
         {:ok, loaded} <- normalize_result(Ash.Type.cast_stored(type.ash_type, native, type.constraints)),
         {:ok, rdf, semantic_loaded} <- semantic_round_trip(type, loaded),
         true <- Ash.Type.equal?(type.ash_type, loaded, semantic_loaded) do
      {:ok,
       %{
         semantic_type_id: type.id,
         input: value,
         casted: casted,
         native: native,
         loaded: loaded,
         rdf: rdf,
         restored: semantic_loaded
       }}
    else
      false ->
        {:error, Refusal.new(:REFUSED_SEMANTIC_ROUND_TRIP, type.name, "semantic round trip changed the value")}

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_SEMANTIC_ROUND_TRIP,
           type.name,
           "semantic type round trip failed",
           %{reason: inspect(reason)}
         )}

      :error ->
        {:error, Refusal.new(:REFUSED_SEMANTIC_ROUND_TRIP, type.name, "Ash type rejected the value")}
    end
  end

  @spec admit_property(SemanticType.t(), atom() | module()) :: :ok | {:error, Refusal.t()}
  def admit_property(%SemanticType{} = type, ash_type) do
    cond do
      type.semantic_kind in [:value_object, :resource] ->
        {:error,
         Refusal.new(
           :REFUSED_SEMANTIC_TYPE_REQUIRES_RESOURCE_PROJECTION,
           type.name,
           "value-object/resource semantics cannot be collapsed into a scalar R2RML property map",
           %{semantic_kind: type.semantic_kind}
         )}

      semantic_ash_compatible?(type, ash_type) ->
        :ok

      true ->
        {:error,
         Refusal.new(
           :REFUSED_SEMANTIC_TYPE_ASH_MISMATCH,
           type.name,
           "Ash attribute type does not match the admitted semantic projection",
           %{expected: inspect(type.ash_type), observed: inspect(ash_type)}
         )}
    end
  end

  defp compile_entry(iri, opts) when is_binary(iri), do: resolve(iri, opts)

  defp compile_entry(%{} = entry, opts) do
    iri = get(entry, :iri) || get(entry, :source_iri)
    raw_selected = get(entry, :selected_representation)
    selected = representation(raw_selected)

    if not is_nil(raw_selected) and is_nil(selected) do
      {:error,
       Refusal.new(
         :REFUSED_SEMANTIC_TYPE_REPRESENTATION,
         iri,
         "unknown semantic type representation",
         %{selected: raw_selected, allowed: @representation_atoms}
       )}
    else
      overrides =
        [
          selected_representation: selected,
          concept_scheme_iri: get(entry, :concept_scheme_iri),
          quantity_kind: get(entry, :quantity_kind),
          allowed_units: get(entry, :allowed_units),
          name: existing_atom(get(entry, :name))
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)

      with {:ok, type} <- resolve(iri, Keyword.merge(opts, overrides)),
           {:ok, type} <- apply_entry_overrides(type, entry) do
        {:ok, type}
      end
    end
  end

  defp compile_entry(other, _opts),
    do:
      {:error,
       Refusal.new(
         :REFUSED_SEMANTIC_PROFILE_INVALID,
         other,
         "semantic type entry must be an IRI or map"
       )}

  defp apply_overrides(type, opts) do
    attrs =
      %{
        selected_representation: Keyword.get(opts, :selected_representation, type.selected_representation),
        concept_scheme_iri: Keyword.get(opts, :concept_scheme_iri, type.concept_scheme_iri)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    AshR2RML.SemanticType.DfCM.select(struct(type, attrs))
  end

  defp apply_entry_overrides(type, entry) do
    fields = [:concept_scheme_iri, :storage_type, :postgres_type, :constraints, :shacl_constraints, :provenance]

    attrs =
      Enum.reduce(fields, %{}, fn field, acc ->
        case get(entry, field) do
          nil -> acc
          value -> Map.put(acc, field, value)
        end
      end)

    selected = representation(get(entry, :selected_representation))
    attrs = if selected, do: Map.put(attrs, :selected_representation, selected), else: attrs
    name = existing_atom(get(entry, :name))
    attrs = if name, do: Map.put(attrs, :name, name), else: attrs
    AshR2RML.SemanticType.DfCM.select(struct(type, attrs))
  end

  defp verify_type(%SemanticType{} = type) do
    []
    |> maybe_refuse(
      not is_nil(type.source_iri) and not SemanticType.absolute_iri?(type.source_iri),
      :REFUSED_SEMANTIC_TYPE_INVALID,
      type.name,
      "source IRI is not absolute"
    )
    |> maybe_refuse(
      type.semantic_kind == :literal and not SemanticType.absolute_iri?(type.datatype_iri),
      :REFUSED_SEMANTIC_TYPE_INVALID,
      type.name,
      "literal semantic type requires an absolute datatype IRI"
    )
    |> maybe_refuse(
      type.semantic_kind in [:concept, :value_object, :resource] and not SemanticType.absolute_iri?(type.class_iri),
      :REFUSED_SEMANTIC_TYPE_INVALID,
      type.name,
      "semantic kind requires an absolute class IRI"
    )
    |> maybe_refuse(
      not is_nil(type.concept_scheme_iri) and not SemanticType.absolute_iri?(type.concept_scheme_iri),
      :REFUSED_SEMANTIC_TYPE_INVALID,
      type.name,
      "concept scheme IRI is not absolute"
    )
    |> maybe_refuse(
      not is_nil(type.selected_representation) and
        type.selected_representation not in type.representation_candidates,
      :REFUSED_SEMANTIC_TYPE_REPRESENTATION,
      type.name,
      "selected representation is outside the candidate set"
    )
  end

  defp maybe_refuse(acc, false, _code, _subject, _detail), do: acc
  defp maybe_refuse(acc, true, code, subject, detail), do: acc ++ [Refusal.new(code, subject, detail)]

  defp semantic_round_trip(%SemanticType{ash_type: ash_type}, loaded) do
    if AshR2RML.Type.semantic_type?(ash_type) do
      with {:ok, rdf} <- encode_rdf(ash_type, loaded),
           {:ok, restored} <- AshR2RML.Type.decode(ash_type, rdf) do
        {:ok, rdf, restored}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, {:projection_value, loaded}, loaded}
    end
  end

  defp encode_rdf(ash_type, loaded) do
    case AshR2RML.Type.encode(ash_type, loaded) do
      {:error, reason} -> {:error, reason}
      rdf -> {:ok, rdf}
    end
  end

  defp normalize_result({:ok, value}), do: {:ok, value}
  defp normalize_result({:error, reason}), do: {:error, reason}
  defp normalize_result(:error), do: :error

  defp semantic_ash_compatible?(%SemanticType{ash_type: expected}, observed) when expected == observed,
    do: true

  defp semantic_ash_compatible?(%SemanticType{semantic_kind: kind}, observed) when kind in [:iri, :concept],
    do: observed in [:string, Ash.Type.String] or AshR2RML.Type.semantic_type?(observed)

  defp semantic_ash_compatible?(_type, _observed), do: false

  defp plan_hash(types, providers) do
    {providers, Enum.map(types, &SemanticType.canonical/1)}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp manifest_type(type), do: type |> SemanticType.canonical() |> Map.put(:id, type.id)
  defp normalize_manifest(%Plan{} = plan), do: manifest(plan)
  defp normalize_manifest(%{} = manifest), do: manifest

  defp index_manifest_types(manifest),
    do: manifest |> get(:types, []) |> Map.new(fn type -> {type_identity(type), type} end)

  defp type_identity(type), do: get(type, :source_iri) || to_string(get(type, :name))

  defp semantic_differences(left, right) do
    [
      :semantic_kind,
      :ash_type,
      :datatype_iri,
      :class_iri,
      :concept_scheme_iri,
      :selected_representation,
      :constraints,
      :shacl_constraints
    ]
    |> Enum.filter(fn field -> normalize_compare(get(left, field)) != normalize_compare(get(right, field)) end)
  end

  defp normalize_compare(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_compare(value) when is_list(value), do: Enum.map(value, &normalize_compare/1)

  defp normalize_compare(value) when is_map(value),
    do: Map.new(value, fn {key, item} -> {normalize_compare(key), normalize_compare(item)} end)

  defp normalize_compare(value), do: value

  defp type_key(type), do: type.source_iri || Atom.to_string(type.name)
  defp representation(nil), do: nil
  defp representation(value) when value in @representation_atoms, do: value
  defp representation(value) when is_binary(value), do: Enum.find(@representation_atoms, &(Atom.to_string(&1) == value))
  defp representation(_), do: nil

  defp existing_atom(nil), do: nil
  defp existing_atom(value) when is_atom(value), do: value

  defp existing_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> nil
    end
  end

  defp entry?(map), do: is_binary(get(map, :iri)) or is_binary(get(map, :source_iri))

  defp get(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
end
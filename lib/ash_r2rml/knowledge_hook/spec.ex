# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Trigger do
  @moduledoc "Normalized trigger specification. A trigger describes observation relevance; it owns no scheduler or DO authority."

  @enforce_keys [:type]
  defstruct [:type, :pattern, observed_receipt_required?: false]

  @type t :: %__MODULE__{
          type: :rdf_change | :sparql_result | :interval | :event,
          pattern: term(),
          observed_receipt_required?: boolean()
        }
end

defmodule AshR2RML.KnowledgeHook.Observation do
  @moduledoc "Minimum semantic observation projection required by a hook."

  @enforce_keys [:kind]
  defstruct [:kind, :query_sha256, :query_form, :projection, :source]

  @type t :: %__MODULE__{
          kind: atom(),
          query_sha256: String.t() | nil,
          query_form: atom() | nil,
          projection: term(),
          source: term()
        }
end

defmodule AshR2RML.KnowledgeHook.Construct do
  @moduledoc "Inert consequence description manufactured by a hook. Never an executable callback."

  @enforce_keys [:kind, :target]
  defstruct [:kind, :target, payload: %{}]

  @type t :: %__MODULE__{kind: atom() | String.t(), target: term(), payload: map()}
end

defmodule AshR2RML.KnowledgeHook.ReceiptPolicy do
  @moduledoc "Receipt obligations carried by a hook specification."

  defstruct evaluation_required?: true,
            actuation_required?: true,
            consequence_required?: true

  @type t :: %__MODULE__{
          evaluation_required?: true,
          actuation_required?: true,
          consequence_required?: true
        }
end

defmodule AshR2RML.KnowledgeHook.Spec do
  @moduledoc """
  Canonical, content-addressed Knowledge Hook IR.

  This structure is the convergence target for normalized maps, GitVan hooks,
  KNHK hooks, and future ontology-generated hook definitions. It is pure data.
  `authority_ceiling` is mechanically fixed to `:CONSTRUCT`.
  """

  alias AshR2RML.KnowledgeHook.{Construct, Definition, Observation, ReceiptPolicy, Trigger}
  alias AshR2RML.{Compiler, Refusal}

  @enforce_keys [
    :id,
    :name,
    :trigger,
    :observation,
    :predicate,
    :construct,
    :receipt_policy,
    :spec_sha256
  ]
  defstruct [
    :id,
    :name,
    :trigger,
    :observation,
    :predicate,
    :construct,
    :receipt_policy,
    :spec_sha256,
    dependencies: [],
    provenance: %{},
    authority_ceiling: :CONSTRUCT,
    status: :PARTIAL_ALIVE,
    standing: :admitted_construct_only
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          trigger: Trigger.t(),
          observation: Observation.t(),
          predicate: AshR2RML.KnowledgeHook.Predicate.t(),
          construct: Construct.t(),
          receipt_policy: ReceiptPolicy.t(),
          spec_sha256: String.t(),
          dependencies: [String.t()],
          provenance: map(),
          authority_ceiling: :CONSTRUCT,
          status: :PARTIAL_ALIVE,
          standing: :admitted_construct_only
        }

  @doc "Compile an admitted hook definition to the canonical content-addressed IR."
  @spec from_definition(Definition.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def from_definition(%Definition{} = definition) do
    dependencies = dependencies(definition)

    with :ok <- validate_dependencies(definition.id, dependencies) do
      trigger = %Trigger{
        type: definition.trigger_type,
        pattern: definition.trigger_pattern,
        observed_receipt_required?: definition.predicate.type == :external_trigger
      }

      observation = %Observation{
        kind: definition.predicate.type,
        query_sha256: definition.predicate.query_sha256,
        query_form: definition.predicate.query_form,
        projection: observation_projection(definition),
        source: provenance_value(definition.provenance, :observation_source)
      }

      construct = %Construct{
        kind: definition.intent.kind,
        target: definition.intent.target,
        payload: definition.intent.payload || %{}
      }

      receipt_policy = %ReceiptPolicy{}

      core = %{
        version: 1,
        id: definition.id,
        name: definition.name,
        trigger: canonical(trigger),
        observation: canonical(observation),
        predicate: canonical_predicate(definition.predicate),
        construct: canonical(construct),
        dependencies: dependencies,
        provenance: canonical(definition.provenance),
        receipt_policy: canonical(receipt_policy),
        authority_ceiling: :CONSTRUCT
      }

      {:ok,
       %__MODULE__{
         id: definition.id,
         name: definition.name,
         trigger: trigger,
         observation: observation,
         predicate: definition.predicate,
         construct: construct,
         dependencies: dependencies,
         provenance: definition.provenance,
         receipt_policy: receipt_policy,
         authority_ceiling: :CONSTRUCT,
         spec_sha256: Compiler.sha256(core)
       }}
    end
  end

  @doc "Compile every hook in an admitted plan to canonical IR."
  @spec from_plan(AshR2RML.KnowledgeHook.Plan.t()) :: {:ok, [t()]} | {:error, Refusal.t()}
  def from_plan(%AshR2RML.KnowledgeHook.Plan{hooks: hooks}) do
    Enum.reduce_while(hooks, {:ok, []}, fn hook, {:ok, acc} ->
      case from_definition(hook) do
        {:ok, spec} -> {:cont, {:ok, [spec | acc]}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, specs} -> {:ok, Enum.reverse(specs)}
      error -> error
    end
  end

  @doc "Stable serializable projection used by generators, receipts, and replay."
  @spec projection(t()) :: map()
  def projection(%__MODULE__{} = spec) do
    %{
      version: 1,
      id: spec.id,
      name: spec.name,
      trigger: canonical(spec.trigger),
      observation: canonical(spec.observation),
      predicate: canonical_predicate(spec.predicate),
      construct: canonical(spec.construct),
      dependencies: spec.dependencies,
      provenance: canonical(spec.provenance),
      receipt_policy: canonical(spec.receipt_policy),
      authority_ceiling: :CONSTRUCT,
      authority: :UNAUTHORIZED,
      standing: spec.standing,
      spec_sha256: spec.spec_sha256
    }
  end

  defp dependencies(%Definition{provenance: provenance}) do
    provenance
    |> provenance_value(:after, provenance_value(provenance, :dependencies, []))
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_dependencies(id, dependencies) do
    if id in dependencies do
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         id,
         "Knowledge Hook cannot depend on itself",
         %{dependencies: dependencies}
       )}
    else
      :ok
    end
  end

  defp observation_projection(definition) do
    provenance_value(definition.provenance, :observation_projection, %{
      predicate_type: definition.predicate.type,
      query_sha256: definition.predicate.query_sha256
    })
  end

  defp canonical_predicate(predicate) do
    %{
      type: predicate.type,
      query_sha256: predicate.query_sha256,
      query_form: predicate.query_form,
      query: predicate.query && predicate.query.source
    }
  end

  defp provenance_value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(value), do: value
end

defmodule AshR2RML.KnowledgeHook.Scheduler do
  @moduledoc "Deterministic dependency scheduler for canonical Knowledge Hook specs. It schedules evaluation only; it never executes intents."

  alias AshR2RML.KnowledgeHook.Spec
  alias AshR2RML.Refusal

  @doc "Topologically order hooks with lexicographic tie-breaking. Missing dependencies and cycles fail closed."
  @spec schedule([Spec.t()]) :: {:ok, [Spec.t()]} | {:error, Refusal.t()}
  def schedule(specs) when is_list(specs) do
    by_id = Map.new(specs, &{&1.id, &1})

    with :ok <- unique_ids(specs),
         :ok <- all_dependencies_exist(specs, by_id) do
      do_schedule(by_id, MapSet.new(), [])
    end
  end

  defp unique_ids(specs) do
    ids = Enum.map(specs, & &1.id)

    if length(ids) == MapSet.size(MapSet.new(ids)) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hook_schedule,
         "canonical Knowledge Hook specs must have unique ids"
       )}
    end
  end

  defp all_dependencies_exist(specs, by_id) do
    missing =
      specs
      |> Enum.flat_map(fn spec ->
        Enum.reject(spec.dependencies, &Map.has_key?(by_id, &1))
        |> Enum.map(&{spec.id, &1})
      end)
      |> Enum.sort()

    if missing == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hook_schedule,
         "Knowledge Hook dependency is absent from the admitted plan",
         %{missing_dependencies: missing}
       )}
    end
  end

  defp do_schedule(by_id, completed, acc) do
    if map_size(by_id) == MapSet.size(completed) do
      {:ok, Enum.reverse(acc)}
    else
      ready =
        by_id
        |> Map.values()
        |> Enum.reject(&MapSet.member?(completed, &1.id))
        |> Enum.filter(fn spec -> Enum.all?(spec.dependencies, &MapSet.member?(completed, &1)) end)
        |> Enum.sort_by(& &1.id)

      case ready do
        [] ->
          unresolved =
            by_id
            |> Map.values()
            |> Enum.reject(&MapSet.member?(completed, &1.id))
            |> Enum.map(fn spec -> {spec.id, spec.dependencies} end)
            |> Enum.sort()

          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :knowledge_hook_schedule,
             "Knowledge Hook dependency graph contains a cycle",
             %{unresolved: unresolved}
           )}

        [next | _] ->
          do_schedule(by_id, MapSet.put(completed, next.id), [next | acc])
      end
    end
  end
end

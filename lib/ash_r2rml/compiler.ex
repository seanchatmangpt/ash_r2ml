# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.CompilationReceipt do
  @moduledoc "Identity and standing record for one deterministic semantic compilation."

  defstruct [
    :status,
    :standing,
    :ontology_hash,
    :profile_hash,
    :shacl_input_hash,
    :ir_sha256,
    :mapping_sha256,
    :ash_sha256,
    :ecto_sha256,
    :postgres_sha256,
    :r2rml_sha256,
    :shacl_sha256,
    :query_parity,
    :cutover_authority,
    classes_admitted: 0,
    attributes_admitted: 0,
    relationships_admitted: 0,
    actions_admitted: 0,
    policies_admitted: 0,
    storage_candidates: %{},
    selected_storage: %{},
    executed: [],
    verified: [],
    blocked: [],
    refusals: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          ontology_hash: String.t() | nil,
          profile_hash: String.t() | nil,
          shacl_input_hash: String.t() | nil,
          ir_sha256: String.t() | nil,
          mapping_sha256: String.t() | nil,
          ash_sha256: String.t() | nil,
          ecto_sha256: String.t() | nil,
          postgres_sha256: String.t() | nil,
          r2rml_sha256: String.t() | nil,
          shacl_sha256: String.t() | nil,
          query_parity: :UNKNOWN | :VERIFIED,
          cutover_authority: :UNAUTHORIZED | :AUTHORIZED | nil,
          classes_admitted: non_neg_integer(),
          attributes_admitted: non_neg_integer(),
          relationships_admitted: non_neg_integer(),
          actions_admitted: non_neg_integer(),
          policies_admitted: non_neg_integer(),
          storage_candidates: map(),
          selected_storage: map(),
          executed: list(),
          verified: list(),
          blocked: list(),
          refusals: list()
        }
end

defmodule AshR2RML.Compilation do
  @moduledoc "Evidence-bounded result of ontology-first semantic compilation."

  defstruct [
    :status,
    :standing,
    :ir,
    :mapping_bundle,
    :ash_source,
    :ecto_migration,
    :postgres_ddl,
    :r2rml,
    :shacl,
    :receipt,
    refusals: []
  ]

  @type t :: %__MODULE__{
          status: atom(),
          standing: atom(),
          ir: AshR2RML.SemanticIR.t() | nil,
          mapping_bundle: AshR2RML.Mapping.Bundle.t() | nil,
          ash_source: String.t() | nil,
          ecto_migration: String.t() | nil,
          postgres_ddl: String.t() | nil,
          r2rml: String.t() | nil,
          shacl: String.t() | nil,
          receipt: AshR2RML.CompilationReceipt.t() | nil,
          refusals: list()
        }
end

defmodule AshR2RML.Compiler do
  @moduledoc """
  Ontology-first compiler for the admitted closed operational profile.

  Pipeline:

      ontology/profile/SHACL-normalized input
          -> Admission
          -> SemanticIR
          -> AshR2RML.Mapping.Bundle
          -> Ash + Ecto + PostgreSQL + R2RML + SHACL
          -> CompilationReceipt

  The canonical public mapping bundle is the serialization boundary. The R2RML
  renderer never reaches back into SemanticIR or Ash to rediscover decisions.

  This is CONSTRUCT only. It neither applies migrations nor starts an OBDA
  service, and therefore cannot grant cutover standing by itself.
  """

  alias AshR2RML.{Admission, Compilation, CompilationReceipt, Refusal, SemanticIR}

  @spec explore(map()) :: {:ok, SemanticIR.t()} | {:error, [Refusal.t()]}
  def explore(profile), do: Admission.admit(profile)

  @spec compile(map() | module() | [module()], keyword()) ::
          {:ok, Compilation.t() | AshR2RML.Mapping.Bundle.t()} | {:error, Compilation.t() | Refusal.t()}
  def compile(resources, opts \\ [])

  def compile(resources, _opts) when is_atom(resources) or is_list(resources) do
    case compile_resources(resources) do
      {:ok, bundle} -> {:ok, bundle}
      {:error, refusal} -> {:error, refusal}
    end
  end

  def compile(profile, opts) when is_map(profile) do
    storage_backend = Keyword.get(opts, :storage_backend, :postgres)

    case Admission.admit(profile) do
      {:error, refusals} ->
        {:error,
         %Compilation{
           status: :REFUSED,
           standing: :no_projection,
           refusals: refusals,
           receipt: refusal_receipt(refusals)
         }}

      {:ok, ir} ->
        case projection_refusals(ir) do
          [] ->
            render_all(ir, storage_backend)

          refusals ->
            {:error,
             %Compilation{
               status: :REFUSED,
               standing: :semantic_ir_only,
               ir: ir,
               refusals: refusals,
               receipt: refusal_receipt(refusals, ir)
             }}
        end
    end
  end

  @doc "Cutover requires an observed query-parity witness and an explicit authority receipt."
  def cutover_ready?(%CompilationReceipt{
        query_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }),
      do: true

  def cutover_ready?(_), do: false

  @doc "Attach an externally observed parity receipt without executing the compared systems."
  def attach_parity_witness(%CompilationReceipt{} = receipt, kind, witness)
      when kind == :sparql_sql and is_map(witness) do
    verified? = Map.get(witness, :verified?, Map.get(witness, "verified?", false))
    witness_id = Map.get(witness, :receipt_sha256, Map.get(witness, "receipt_sha256"))

    if verified? and is_binary(witness_id) and witness_id != "" do
      receipt = %{receipt | query_parity: :VERIFIED}
      blocked = List.delete(receipt.blocked, :sparql_sql_behavioral_parity)

      %{
        receipt
        | blocked: blocked,
          verified: Enum.uniq([{:parity_witness, kind, witness_id} | receipt.verified])
      }
    else
      refusal =
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          kind,
          "parity witness must be observed, verified, and carry a stable receipt_sha256",
          %{witness: witness}
        )

      %{receipt | refusals: [refusal | receipt.refusals]}
    end
  end

  @doc "Attach explicit cutover authority without conflating it with technical parity."
  def authorize_cutover(%CompilationReceipt{} = receipt, authority) when is_map(authority) do
    authorized? = Map.get(authority, :authorized?, Map.get(authority, "authorized?", false))
    authority_id = Map.get(authority, :receipt_sha256, Map.get(authority, "receipt_sha256"))

    if authorized? and is_binary(authority_id) and authority_id != "" do
      %{
        receipt
        | cutover_authority: :AUTHORIZED,
          blocked: List.delete(receipt.blocked, :cutover_authority),
          verified: Enum.uniq([{:cutover_authority, authority_id} | receipt.verified])
      }
    else
      refusal =
        Refusal.new(
          :REFUSED_UNPROVEN_EQUIVALENCE,
          :cutover_authority,
          "cutover authority requires authorized?: true and a stable receipt_sha256",
          %{authority: authority}
        )

      %{receipt | refusals: [refusal | receipt.refusals]}
    end
  end

  defp render_all(ir, storage_backend) do
    with {:ok, mapping_bundle} <- AshR2RML.SemanticAdapter.to_mapping(ir),
         :ok <- AshR2RML.Mapping.validate(mapping_bundle),
         {:ok, ash_source} <- AshR2RML.Semantic.Ash.render(ir),
         {:ok, ecto_migration} <- AshR2RML.Semantic.Ecto.render(ir),
         {:ok, postgres_ddl} <- render_storage_ddl(ir, storage_backend),
         {:ok, r2rml} <- AshR2RML.R2RML.render(mapping_bundle),
         {:ok, shacl} <- AshR2RML.Semantic.SHACL.render(ir) do
      compilation_receipt =
        receipt(ir, mapping_bundle, ash_source, ecto_migration, postgres_ddl, r2rml, shacl, storage_backend)

      {:ok,
       %Compilation{
         status: :PARTIAL_ALIVE,
         standing: :constructed_not_actuated,
         ir: ir,
         mapping_bundle: mapping_bundle,
         ash_source: ash_source,
         ecto_migration: ecto_migration,
         postgres_ddl: postgres_ddl,
         r2rml: r2rml,
         shacl: shacl,
         receipt: compilation_receipt,
         refusals: []
       }}
    else
      {:error, [%AshR2RML.Refusal{} = refusal | _]} ->
        public_refusal_compilation(ir, refusal)

      {:error, %AshR2RML.Refusal{} = refusal} ->
        public_refusal_compilation(ir, refusal)

      {:error, reason} ->
        refusal =
          Refusal.new(
            :REFUSED_UNPROVEN_EQUIVALENCE,
            :projection,
            "renderer refused semantic IR",
            %{reason: inspect(reason)}
          )

        refusal_compilation(ir, refusal)
    end
  end

  defp public_refusal_compilation(ir, public_refusal) do
    refusal =
      Refusal.new(
        :REFUSED_UNPROVEN_EQUIVALENCE,
        public_refusal.subject,
        "canonical mapping refused ontology-first projection: #{public_refusal.code}: #{public_refusal.detail}",
        %{public_refusal: Map.from_struct(public_refusal)}
      )

    refusal_compilation(ir, refusal)
  end

  defp refusal_compilation(ir, refusal) do
    {:error,
     %Compilation{
       status: :REFUSED,
       standing: :semantic_ir_only,
       ir: ir,
       refusals: [refusal],
       receipt: refusal_receipt([refusal], ir)
     }}
  end

  defp projection_refusals(ir) do
    Enum.flat_map(ir.resources, fn resource ->
      Enum.flat_map(resource.relationships, fn relationship ->
        cond do
          is_nil(relationship.storage_strategy) ->
            [
              Refusal.new(
                :REFUSED_UNPROVEN_EQUIVALENCE,
                {resource.class_iri, relationship.name},
                "multiple lawful relational representations remain; select only after profile evidence closes the choice",
                %{candidates: relationship.storage_candidates}
              )
            ]

          relationship.storage_strategy == :association_resource ->
            [
              Refusal.new(
                :REFUSED_UNPROVEN_EQUIVALENCE,
                {resource.class_iri, relationship.name},
                "association-resource relationships must be reified as an admitted SemanticResource before executable projection",
                %{association_resource: relationship.association_resource}
              )
            ]

          true ->
            []
        end
      end)
    end)
  end

  # `:postgres` renders a real W3C-standard-adjacent SQL DDL projection via
  # `AshR2RML.Semantic.SQL.render/1`. `:ets` needs no DDL at all -- Ash + `Ash.DataLayer.Ets`
  # own storage automatically -- so this deliberately returns `{:ok, nil}` rather than a
  # BLOCKED/refused outcome; `postgres_ddl: nil` on the resulting `Compilation`/receipt is
  # expected, not a failure, when compiling for the ETS backend.
  defp render_storage_ddl(_ir, :ets), do: {:ok, nil}
  defp render_storage_ddl(ir, :postgres), do: AshR2RML.Semantic.SQL.render(ir)

  defp receipt(ir, mapping_bundle, ash_source, ecto_migration, postgres_ddl, r2rml, shacl, storage_backend) do
    resources = ir.resources

    %CompilationReceipt{
      status: :PARTIAL_ALIVE,
      standing: :constructed_not_actuated,
      ontology_hash: ir.ontology_hash,
      profile_hash: ir.profile_hash,
      shacl_input_hash: ir.shacl_hash,
      ir_sha256: sha256(canonical_ir(ir)),
      mapping_sha256: sha256(canonical_term(mapping_bundle)),
      ash_sha256: sha256(ash_source),
      ecto_sha256: sha256(ecto_migration),
      postgres_sha256: sha256(postgres_ddl),
      r2rml_sha256: sha256(r2rml),
      shacl_sha256: sha256(shacl),
      query_parity: :UNKNOWN,
      cutover_authority: :UNAUTHORIZED,
      classes_admitted: length(resources),
      attributes_admitted: Enum.sum(Enum.map(resources, &length(&1.attributes))),
      relationships_admitted: Enum.sum(Enum.map(resources, &length(&1.relationships))),
      actions_admitted: Enum.sum(Enum.map(resources, &length(&1.actions))),
      policies_admitted: Enum.sum(Enum.map(resources, &length(&1.policies))),
      storage_candidates: storage_map(resources, & &1.storage_candidates),
      selected_storage: storage_map(resources, & &1.storage_strategy),
      executed:
        [
          :admission,
          :semantic_ir,
          :canonical_mapping_ir,
          :ash_render,
          :ecto_render
        ] ++
          storage_render_step(storage_backend) ++
          [
            :r2rml_render,
            :shacl_render
          ],
      verified: [:canonical_mapping_ir_projection, :deterministic_render_identity],
      blocked: [
        :sparql_sql_behavioral_parity,
        :cutover_authority
      ],
      refusals: []
    }
  end

  defp refusal_receipt(refusals, ir \\ nil) do
    %CompilationReceipt{
      status: :REFUSED,
      standing: :no_cutover,
      ontology_hash: ir && ir.ontology_hash,
      profile_hash: ir && ir.profile_hash,
      shacl_input_hash: ir && ir.shacl_hash,
      query_parity: :UNKNOWN,
      cutover_authority: :UNAUTHORIZED,
      blocked: [
        :semantic_projection,
        :sparql_sql_behavioral_parity,
        :cutover_authority
      ],
      refusals: refusals
    }
  end

  defp storage_render_step(:postgres), do: [:postgres_render]
  defp storage_render_step(:ets), do: [:postgres_ddl_skipped_ets_backend]

  defp storage_map(resources, value_fun) do
    Map.new(
      for resource <- resources,
          relationship <- resource.relationships do
        {{resource.class_iri, relationship.name}, value_fun.(relationship)}
      end
    )
  end

  defp canonical_ir(ir), do: canonical_term(ir)

  defp canonical_term(%_{} = struct), do: struct |> Map.from_struct() |> canonical_term()

  defp canonical_term(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical_term(value)} end)
    |> Enum.sort_by(fn {key, _value} -> inspect(key) end)
  end

  defp canonical_term(list) when is_list(list), do: Enum.map(list, &canonical_term/1)
  defp canonical_term(other), do: other

  def compile_resources(resources) do
    resources = List.wrap(resources)

    with {:ok, mappings} <- do_closure(resources, MapSet.new(), []) do
      bundle = %AshR2RML.Mapping.Bundle{resources: mappings} |> AshR2RML.Mapping.normalize()

      case AshR2RML.Mapping.validate(bundle) do
        :ok -> {:ok, bundle}
        {:error, [first | _]} -> {:error, first}
        {:error, []} -> {:ok, bundle}
      end
    end
  end

  defp do_closure([], _seen, acc), do: {:ok, Enum.reverse(acc)}

  defp do_closure([resource | rest], seen, acc) do
    if MapSet.member?(seen, resource) do
      do_closure(rest, seen, acc)
    else
      case AshR2RML.Resource.Info.mapping_result(resource) do
        {:ok, mapping} ->
          mapping = AshR2RML.Security.sanitize_mapping(resource, mapping)
          destinations = Enum.map(mapping.reference_object_maps, & &1.parent_resource) |> Enum.reject(&is_nil/1)

          do_closure(
            rest ++ destinations,
            MapSet.put(seen, resource),
            [mapping | acc]
          )

        {:error, refusal} ->
          {:error, refusal}
      end
    end
  end

  def sha256(value) when is_binary(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
  def sha256(value), do: value |> :erlang.term_to_binary([:deterministic]) |> sha256()
end

defmodule AshR2RML.SemanticAdapter do
  @moduledoc "Lowers ontology-first SemanticIR into the canonical public mapping IR."

  alias AshR2RML.Mapping.{
    Bundle,
    Datatype,
    JoinCondition,
    LogicalTable,
    ObjectMap,
    PredicateObjectMap,
    ReferenceObjectMap,
    Resource,
    SubjectMap
  }

  alias AshR2RML.Refusal

  @spec to_mapping(AshR2RML.SemanticIR.t()) :: {:ok, Bundle.t()} | {:error, Refusal.t()}
  def to_mapping(%AshR2RML.SemanticIR{resources: resources}) do
    by_class = Map.new(resources, &{&1.class_iri, &1})

    Enum.reduce_while(resources, {:ok, []}, fn resource, {:ok, acc} ->
      case convert_resource(resource, by_class) do
        {:ok, mapping} -> {:cont, {:ok, [mapping | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, mappings} -> {:ok, %Bundle{resources: Enum.reverse(mappings)} |> AshR2RML.Mapping.normalize()}
      error -> error
    end
  end

  defp convert_resource(resource, by_class) do
    with {:ok, references} <- convert_references(resource, by_class) do
      properties =
        Enum.map(resource.attributes, fn attribute ->
          %PredicateObjectMap{
            attribute: attribute.name,
            predicate_iri: attribute.predicate_iri,
            object_map: %ObjectMap{
              strategy: :column,
              value: attribute.column,
              datatype: %Datatype{
                ash_type: attribute.ash_type,
                rdf_datatype: attribute.datatype_iri,
                storage_type: attribute.postgres_type
              },
              term_type: :literal
            }
          }
        end)

      attribute_columns = Map.new(resource.attributes, &{&1.name, &1.column})

      {:ok,
       %Resource{
         ash_resource: resource.module,
         class_iris: [resource.class_iri],
         logical_table: %LogicalTable{table_name: resource.table},
         subject_map: %SubjectMap{
           strategy: :template,
           value: resource.subject_template,
           term_type: :iri
         },
         predicate_object_maps: properties,
         reference_object_maps: references,
         identities: Enum.map(resource.identities, & &1.keys),
         metadata: %{
           attribute_columns: attribute_columns,
           shape_iri: resource.shape_iri,
           provenance: resource.provenance,
           source: :ontology_first
         }
       }
       |> AshR2RML.Mapping.normalize()}
    end
  end

  defp convert_references(resource, by_class) do
    Enum.reduce_while(resource.relationships, {:ok, []}, fn relationship, {:ok, acc} ->
      destination = Map.get(by_class, relationship.target_class)

      cond do
        is_nil(destination) ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_RELATIONSHIP_TARGET_UNMAPPED,
              {resource.module, relationship.name},
              "ontology-first relationship target is absent from admitted SemanticIR",
              %{target_class: relationship.target_class}
            )}}

        relationship.storage_strategy == :foreign_key ->
          child = attribute_column(resource, relationship.source_key)
          parent = attribute_column(destination, relationship.destination_key)

          mapping = %ReferenceObjectMap{
            relationship: relationship.name,
            predicate_iri: relationship.predicate_iri,
            inverse_predicate: relationship.inverse_predicate,
            parent_resource: destination.module,
            joins: [%JoinCondition{child: child, parent: parent}],
            metadata: %{kind: :foreign_key, cardinality: relationship.cardinality}
          }

          {:cont, {:ok, [mapping | acc]}}

        relationship.storage_strategy == :join_table ->
          source_parent = attribute_column(resource, relationship.source_key)
          destination_parent = attribute_column(destination, relationship.destination_key)

          metadata = %{
            kind: :many_to_many,
            cardinality: :many,
            through_logical_table: %LogicalTable{table_name: relationship.join_table},
            source_parent_column: source_parent,
            source_join_column: relationship.source_join_column,
            destination_join_column: relationship.destination_join_column,
            destination_parent_column: destination_parent
          }

          mapping = %ReferenceObjectMap{
            relationship: relationship.name,
            predicate_iri: relationship.predicate_iri,
            inverse_predicate: relationship.inverse_predicate,
            parent_resource: destination.module,
            joins: [],
            metadata: metadata
          }

          {:cont, {:ok, [mapping | acc]}}

        relationship.storage_strategy == :association_resource ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_AMBIGUOUS_RELATIONSHIP,
              {resource.module, relationship.name},
              "association-resource semantics must be represented by an admitted resource before public mapping compilation",
              %{association_resource: relationship.association_resource}
            )}}

        true ->
          {:halt,
           {:error,
            Refusal.new(
              :REFUSED_AMBIGUOUS_RELATIONSHIP,
              {resource.module, relationship.name},
              "ontology-first relationship storage remains unresolved",
              %{storage_strategy: relationship.storage_strategy, candidates: relationship.storage_candidates}
            )}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp attribute_column(resource, name) do
    case Enum.find(resource.attributes, &(&1.name == name)) do
      nil -> to_string(name)
      attribute -> attribute.column
    end
  end
end

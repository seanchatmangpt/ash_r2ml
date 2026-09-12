# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SemanticIR.Identity do
  @moduledoc "Semantic identity used by Ash, SQL uniqueness, and rr:template admission."

  @enforce_keys [:name, :keys]
  defstruct [:name, :template, primary?: false, keys: []]

  @type t :: %__MODULE__{
          name: atom(),
          keys: [atom()],
          template: String.t() | nil,
          primary?: boolean()
        }
end

defmodule AshR2RML.SemanticIR.Attribute do
  @moduledoc "One admitted datatype-property projection across semantic, Ash, and SQL worlds."

  @enforce_keys [:name, :predicate_iri, :datatype_iri, :ash_type, :postgres_type]
  defstruct [
    :name,
    :column,
    :predicate_iri,
    :datatype_iri,
    :ash_type,
    :postgres_type,
    min_count: 0,
    max_count: 1,
    nullable: true,
    identity?: false,
    provenance: %{}
  ]

  @type t :: %__MODULE__{
          name: atom(),
          column: String.t(),
          predicate_iri: String.t(),
          datatype_iri: String.t(),
          ash_type: atom() | module(),
          postgres_type: String.t(),
          min_count: non_neg_integer(),
          max_count: non_neg_integer() | nil,
          nullable: boolean(),
          identity?: boolean(),
          provenance: map()
        }
end

defmodule AshR2RML.SemanticIR.Relationship do
  @moduledoc """
  Admitted object-property projection.

  `storage_candidates` preserves reversible lawful relational representations.
  `storage_strategy` is populated only when the profile or deterministic
  constraints authorize selection. Candidate membership does not imply that the
  current compiler implements the selected representation.
  """

  @enforce_keys [:name, :predicate_iri, :source_class, :target_class]
  defstruct [
    :name,
    :predicate_iri,
    :inverse_predicate,
    :source_class,
    :target_class,
    :source_key,
    :destination_key,
    :join_table,
    :source_join_column,
    :destination_join_column,
    :association_resource,
    :storage_strategy,
    min_count: 0,
    max_count: nil,
    cardinality: :many,
    storage_candidates: [],
    properties: [],
    provenance: %{}
  ]

  @type storage_strategy ::
          :foreign_key
          | :join_table
          | :association_resource
          | :array
          | :jsonb
          | :computed_projection

  @type t :: %__MODULE__{
          name: atom(),
          predicate_iri: String.t(),
          inverse_predicate: String.t() | nil,
          source_class: String.t(),
          target_class: String.t(),
          min_count: non_neg_integer(),
          max_count: non_neg_integer() | nil,
          cardinality: :one | :many,
          storage_strategy: storage_strategy() | nil,
          storage_candidates: [storage_strategy()],
          source_key: atom() | nil,
          destination_key: atom() | nil,
          join_table: String.t() | nil,
          source_join_column: String.t() | nil,
          destination_join_column: String.t() | nil,
          association_resource: module() | String.t() | nil,
          properties: list(),
          provenance: map()
        }
end

defmodule AshR2RML.SemanticIR.Action do
  @moduledoc "Verb projection. Actions are not manufactured as RDF classes by default."

  @enforce_keys [:name]
  defstruct [:name, :kind, :input_shape, :output_shape, provenance: %{}]

  @type t :: %__MODULE__{
          name: atom(),
          kind: atom() | nil,
          input_shape: term(),
          output_shape: term(),
          provenance: map()
        }
end

defmodule AshR2RML.SemanticIR.Policy do
  @moduledoc "Authorization/governance projection aligned separately from ontology classes."

  @enforce_keys [:name]
  defstruct [:name, :effect, :expression, :odrl_iri, provenance: %{}]

  @type t :: %__MODULE__{
          name: atom(),
          effect: atom() | nil,
          expression: term(),
          odrl_iri: String.t() | nil,
          provenance: map()
        }
end

defmodule AshR2RML.SemanticIR.Resource do
  @moduledoc "Closed operational projection of an admitted class/shape pair."

  @enforce_keys [:iri, :class_iri, :shape_iri, :module, :table, :subject_template]
  defstruct [
    :iri,
    :class_iri,
    :shape_iri,
    :module,
    :repo_module,
    :table,
    :subject_template,
    identities: [],
    attributes: [],
    relationships: [],
    actions: [],
    policies: [],
    provenance: %{}
  ]

  @type t :: %__MODULE__{
          iri: String.t(),
          class_iri: String.t(),
          shape_iri: String.t(),
          module: module() | String.t(),
          repo_module: module() | String.t() | nil,
          table: String.t(),
          subject_template: String.t(),
          identities: [AshR2RML.SemanticIR.Identity.t()],
          attributes: [AshR2RML.SemanticIR.Attribute.t()],
          relationships: [AshR2RML.SemanticIR.Relationship.t()],
          actions: [AshR2RML.SemanticIR.Action.t()],
          policies: [AshR2RML.SemanticIR.Policy.t()],
          provenance: map()
        }
end

defmodule AshR2RML.DfCM do
  @moduledoc "Degree-of-Freedom Calculus for Relationship Storage Topology Selection."

  alias AshR2RML.Refusal
  alias AshR2RML.SemanticIR.Relationship

  @spec storage_candidates(Relationship.t()) :: [Relationship.storage_strategy()]
  def storage_candidates(%Relationship{cardinality: :one}) do
    [:foreign_key, :join_table, :association_resource]
  end

  def storage_candidates(%Relationship{cardinality: :many}) do
    [:foreign_key, :join_table, :association_resource, :array, :jsonb, :computed_projection]
  end

  def storage_candidates(_), do: [:foreign_key, :join_table, :association_resource]

  @spec select(Relationship.t()) :: {:ok, Relationship.t()} | {:error, Refusal.t()}
  def select(%Relationship{} = relationship) do
    candidates = storage_candidates(relationship)
    relationship = %{relationship | storage_candidates: candidates}

    case relationship.storage_strategy do
      nil ->
        {:ok, relationship}

      strategy when strategy in [:array, :jsonb, :computed_projection] ->
        {:error,
         Refusal.new(
           :REFUSED_PROJECTION_NOT_IMPLEMENTED,
           relationship.name,
           "storage strategy #{inspect(strategy)} is not implemented by current compiler",
           %{strategy: strategy, candidates: candidates}
         )}

      strategy ->
        if strategy in candidates do
          {:ok, relationship}
        else
          {:error,
           Refusal.new(
             :REFUSED_AMBIGUOUS_RELATIONSHIP,
             relationship.name,
             "invalid storage strategy specified for relationship",
             %{strategy: strategy, candidates: candidates}
           )}
        end
    end
  end
end

defmodule AshR2RML.SemanticIR do
  @moduledoc """
  Canonical ontology-first compilation object.

  The IR is intentionally independent of Ash source, Ecto migrations,
  PostgreSQL DDL, R2RML serialization, and SHACL serialization. Those are
  projections of this object, not independent authoring surfaces.
  """

  defstruct ontology_hash: nil,
            profile_hash: nil,
            shacl_hash: nil,
            resources: []

  @type t :: %__MODULE__{
          ontology_hash: String.t() | nil,
          profile_hash: String.t() | nil,
          shacl_hash: String.t() | nil,
          resources: [AshR2RML.SemanticIR.Resource.t()]
        }
end

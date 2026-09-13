# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.GrandExample.Types.SemVer do
  @moduledoc """
  Custom Ash semantic version scalar type with standards-valid XSD datatype representation for test suites.
  """
  use Ash.Type

  use AshR2RML.Type,
    xsd_datatype: "http://www.w3.org/2001/XMLSchema#string"

  @impl Ash.Type
  def storage_type(_), do: :string

  @impl Ash.Type
  def cast_input(value, _) when is_binary(value), do: {:ok, value}
  def cast_input(%{major: maj, minor: min, patch: pat}, _), do: {:ok, "#{maj}.#{min}.#{pat}"}
  def cast_input(_, _), do: {:error, "Invalid SemVer format"}

  @impl Ash.Type
  def cast_stored(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_native(value, _), do: {:ok, to_string(value)}

  @impl Ash.Type
  def dump_to_embedded(value, _), do: {:ok, to_string(value)}

  @impl AshR2RML.Type
  def to_rdf_lexical(value), do: "v#{value}"
end

defmodule AshR2RML.GrandExample.Domain do
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshR2RML.GrandExample.Organization
    resource AshR2RML.GrandExample.Person
    resource AshR2RML.GrandExample.SemanticManifest
    resource AshR2RML.GrandExample.Warehouse
    resource AshR2RML.GrandExample.Shipment
  end
end

defmodule AshR2RML.GrandExample.Organization do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  # private?(true): this fixture is shared across obda_in_memory_test.exs,
  # grand_example_e2e_test.exs, zach_post_agi_reactor_test.exs,
  # ocel_telemetry_chicago_test.exs, and obda_adapter_test.exs, all `async: true`.
  # Ash.DataLayer.Ets's default (`private?: false`) backs the table with a single
  # named GenServer shared across processes -- concurrent tests racing a create
  # against another test's teardown intermittently raised `:table_not_found`
  # (real, reproduced flake). `private?(true)` scopes the ETS table to the
  # calling test process, eliminating the shared mutable state entirely; no test
  # here reads/writes this resource from more than one process.
  ets do
    private? true
  end

  r2rml do
    class_iri("https://schema.org/Organization")
    subject_template("https://schema.org/Organization/{id}")
    table_name("schema_organizations")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:version, "https://schema.org/version"}
    ])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :version]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :version, AshR2RML.GrandExample.Types.SemVer, allow_nil?: false, public?: true
    timestamps()
  end
end

defmodule AshR2RML.GrandExample.Person do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  # See AshR2RML.GrandExample.Organization's `ets do private?(true) end` comment.
  ets do
    private? true
  end

  r2rml do
    class_iri("https://schema.org/Person")
    subject_template("https://schema.org/Person/{id}")
    table_name("schema_people")

    attribute_mappings([
      {:name, "https://schema.org/name"},
      {:email, "https://schema.org/email"}
    ])

    relationship_mappings([
      {:organization, "https://schema.org/memberOf"}
    ])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:name, :email, :organization_id]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :string, allow_nil?: false, public?: true
    attribute :organization_id, :uuid, allow_nil?: true, public?: true
    timestamps()
  end

  relationships do
    belongs_to :organization, AshR2RML.GrandExample.Organization do
      source_attribute :organization_id
      destination_attribute :id
      attribute_writable? true
    end
  end
end

defmodule AshR2RML.GrandExample.SemanticManifest do
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  # See AshR2RML.GrandExample.Organization's `ets do private?(true) end` comment.
  ets do
    private? true
  end

  r2rml do
    class_iri("https://schema.org/Dataset")
    subject_template("https://schema.org/Dataset/{id}")
    table_name("schema_datasets")

    attribute_mappings([
      {:title, "https://schema.org/headline"},
      {:status, "https://schema.org/creativeWorkStatus"},
      {:published_turtle, "https://schema.org/text"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :title, :string, allow_nil?: false, public?: true
    attribute :status, :atom, default: :draft, constraints: [one_of: [:draft, :published, :archived]], public?: true
    attribute :published_turtle, :string, allow_nil?: true, public?: true
    timestamps()
  end

  actions do
    defaults [:read, :destroy]

    create :create_manifest do
      primary? true
      accept [:title, :status, :published_turtle]
    end

    update :mark_published do
      accept [:status, :published_turtle]
      change set_attribute(:status, :published)
    end

    update :revert_status do
      accept [:status]
      change set_attribute(:status, :draft)
    end
  end
end

defmodule AshR2RML.GrandExample.Warehouse do
  @moduledoc """
  Composite natural-key parent resource (`{region, code}`) for R2RML-107's real
  multi-column `rr:joinCondition` test fixture -- `Shipment` below joins to this
  resource on two columns at once, exercising `AshR2RML.OBDA.InMemory`'s composite-key
  resolution rather than the single-column foreign-key case every other fixture here
  already covers.

  Deliberately does **not** use the `AshR2RML` extension/`r2rml` DSL: `VerifyMapping`
  enforces a real, project-wide invariant that a resource's `subject_template` must
  contain its physical primary-key placeholder (`{id}`), which is correct for every
  other fixture here but is exactly the case this composite-key semantic identity
  (`{region, code}`, not `{id}`) needs to *not* hold -- that is the whole point of a
  composite natural key. Rather than weakening that invariant (out of this ticket's
  scope) or fabricating a fake `{id}` placeholder into the template (which would leave
  an unsubstituted, invalid IRI fragment once the composite join only substitutes
  `region`/`code`), the test builds this resource's `AshR2RML.Mapping.Resource` by
  hand -- the same pattern `test/obda_in_memory_test.exs`'s "refuses unsupported
  subject-map strategies" test already uses -- while every row still comes from a
  real `Ash.create!`/`Ash.read!` call against this real `Ash.DataLayer.Ets` resource.
  """
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets

  # See AshR2RML.GrandExample.Organization's `ets do private?(true) end` comment.
  ets do
    private? true
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:region, :code, :name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :region, :string, allow_nil?: false, public?: true
    attribute :code, :string, allow_nil?: false, public?: true
    attribute :name, :string, allow_nil?: false, public?: true
  end
end

defmodule AshR2RML.GrandExample.Shipment do
  @moduledoc """
  Child resource carrying both halves (`:region`, `:warehouse_code`) of a composite
  foreign key into `Warehouse`'s `{region, code}` natural key. The R2RML DSL's
  `relationship_mappings` only introspects single-column Ash `belongs_to`
  `source_attribute`/`destination_attribute` pairs, so this composite relationship
  is not declared through that macro -- the test constructs the composite
  `ReferenceObjectMap` by hand against this resource's *real* mapping the same way
  `test/obda_in_memory_test.exs`'s existing hand-built-mapping tests already do,
  while every row still comes from a real `Ash.create!`/`Ash.read!` call.
  """
  use Ash.Resource,
    domain: AshR2RML.GrandExample.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  # See AshR2RML.GrandExample.Organization's `ets do private?(true) end` comment.
  ets do
    private? true
  end

  r2rml do
    class_iri("https://schema.org/Shipment")
    subject_template("https://schema.org/Shipment/{id}")
    table_name("schema_shipments")

    attribute_mappings([
      {:tracking_number, "https://schema.org/identifier"}
    ])
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      primary? true
      accept [:tracking_number, :region, :warehouse_code]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :tracking_number, :string, allow_nil?: false, public?: true
    attribute :region, :string, allow_nil?: false, public?: true
    attribute :warehouse_code, :string, allow_nil?: false, public?: true
  end
end

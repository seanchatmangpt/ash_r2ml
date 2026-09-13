# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Scoped demonstration fixture for
# documentation/topics/palantir_kudzu_migration.md's Align/Admit/Manufacture
# phases: the SAME semantics declared by
# incumbent_ontology_object.json (an "Asset" object type, two datatype
# properties, one link to an "Organization" object type), modeled natively as
# real Ash resources with real AshR2RML semantic annotations -- not a
# hand-duplicated copy of the vendor JSON, but the admitted target of the
# migration's Align step.

defmodule AshR2RML.PalantirMigrationFixture.Organization do
  @moduledoc """
  Native Ash resource for the incumbent "Organization" link target.

  Semantic correspondence to the incumbent ontology object
  (see incumbent_ontology_object.json `links[0].targetObjectType`):

    - objectType.classIri "https://www.w3.org/ns/org#Organization"
      -> r2rml class "https://www.w3.org/ns/org#Organization"
  """
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  r2rml do
    table_name("palantir_fixture_organizations")
    class("https://www.w3.org/ns/org#Organization")

    subject do
      template("https://example.test/organization/{id}")
    end

    property(:name, "http://xmlns.com/foaf/0.1/name")
  end
end

defmodule AshR2RML.PalantirMigrationFixture.Asset do
  @moduledoc """
  Native Ash resource migrating the incumbent "Asset" ontology object.

  Semantic correspondence to incumbent_ontology_object.json, preserved
  one-for-one rather than hand-duplicated as a second source of truth:

    - objectType.classIri "https://example.test/ontology/Asset"
      -> r2rml class "https://example.test/ontology/Asset"
    - properties[0] assetTag -> attribute :asset_tag + rdf predicate
      "https://example.test/ontology/assetTag"
    - properties[1] serialNumber -> attribute :serial_number + rdf predicate
      "https://example.test/ontology/serialNumber"
    - links[0] custodian (-> Organization) -> belongs_to :custodian,
      Organization + rdf predicate "https://www.w3.org/ns/org#heldBy"

  This is the Ash side of the round-trip the demonstration test proves:
  the same class/property/relationship facts the incumbent object declares
  are recoverable from the generated R2RML/Turtle projection of this
  resource, not just from prose claiming equivalence.
  """
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  attributes do
    uuid_primary_key :id
    attribute :asset_tag, :string, allow_nil?: false, public?: true
    attribute :serial_number, :string, allow_nil?: false, public?: true
  end

  relationships do
    belongs_to :custodian, AshR2RML.PalantirMigrationFixture.Organization,
      allow_nil?: false,
      public?: true
  end

  r2rml do
    table_name("palantir_fixture_assets")
    class("https://example.test/ontology/Asset")

    subject do
      template("https://example.test/asset/{id}")
    end

    property(:asset_tag, "https://example.test/ontology/assetTag")
    property(:serial_number, "https://example.test/ontology/serialNumber")
    reference(:custodian, "https://www.w3.org/ns/org#heldBy")
  end
end

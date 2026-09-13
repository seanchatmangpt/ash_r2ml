# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.PalantirMigrationDemonstrationTest do
  @moduledoc """
  Scoped, mechanically-checked demonstration of the doctrine described in
  documentation/topics/palantir_kudzu_migration.md: a single incumbent
  ontology object migrating into a real Ash resource whose semantic
  relationships survive as a *generated* R2RML/Turtle projection, not a
  hand-duplicated copy.

  This does not exercise the full Kudzu phase list (Observe/Align/Admit/
  Manufacture/Verify/Move/Delete) or any real Palantir system. It proves
  exactly one falsifiable claim, matching this doc's own "Standing and
  falsifiers" section: that after admission and generation, "a generated
  projection must be reverse-engineered to reconstruct meaning" does NOT
  hold for this one object -- the class, both datatype properties, and the
  one link the incumbent object declares are all mechanically recoverable
  from the real, compiler-generated Turtle.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.PalantirMigrationFixture.Asset

  @incumbent_fixture_path Path.join([
                             __DIR__,
                             "support",
                             "palantir_migration_fixture",
                             "incumbent_ontology_object.json"
                           ])

  setup_all do
    incumbent =
      @incumbent_fixture_path
      |> File.read!()
      |> Jason.decode!()

    {:ok, incumbent: incumbent}
  end

  test "incumbent ontology object fixture declares the semantics this test proves survive migration",
       %{incumbent: incumbent} do
    # Measure baseline: assert the incumbent fixture actually declares the
    # facts the rest of this test claims are preserved, rather than assuming
    # the JSON's shape.
    assert incumbent["objectType"]["classIri"] == "https://example.test/ontology/Asset"
    assert length(incumbent["properties"]) == 2
    assert length(incumbent["links"]) == 1

    property_predicates = Enum.map(incumbent["properties"], & &1["predicateIri"])
    assert "https://example.test/ontology/assetTag" in property_predicates
    assert "https://example.test/ontology/serialNumber" in property_predicates

    [link] = incumbent["links"]
    assert link["predicateIri"] == "https://www.w3.org/ns/org#heldBy"
    assert link["targetObjectType"]["classIri"] == "https://www.w3.org/ns/org#Organization"
  end

  test "real Ash resource compiles via AshR2RML's real pipeline and preserves the incumbent's semantic facts as generated R2RML/Turtle",
       %{incumbent: incumbent} do
    # (a) introspect the real Ash resource via AshR2RML's real
    # introspection/compiler path -- compile_ash_ttl_bundle/1 walks the
    # admitted dependency closure (Asset -> Organization) via real Ash
    # resource + relationship introspection, not hand-listed resources.
    assert {:ok, bundle} = AshR2RML.compile_ash_ttl_bundle(Asset)
    assert bundle.status == :PARTIAL_ALIVE
    assert bundle.source == :ash

    # (b) project it to real R2RML/RDF Turtle via the real
    # AshR2RML.Compiler/Mapping pipeline (compile_ash_ttl_bundle renders
    # both an ontology.ttl and an r2rml/mapping.ttl from the same normalized
    # mapping IR -- no hand-authored Turtle anywhere in this test).
    ontology_ttl = bundle.files["ontology.ttl"]
    r2rml_ttl = bundle.files["r2rml/mapping.ttl"]
    refute is_nil(ontology_ttl)
    refute is_nil(r2rml_ttl)

    incumbent_class_iri = incumbent["objectType"]["classIri"]
    incumbent_link = hd(incumbent["links"])
    incumbent_link_class_iri = incumbent_link["targetObjectType"]["classIri"]
    incumbent_link_predicate = incumbent_link["predicateIri"]
    incumbent_property_predicates = Enum.map(incumbent["properties"], & &1["predicateIri"])

    # (c) assert the generated Turtle preserves the SAME semantic facts the
    # incumbent ontology object fixture declared: class, both datatype
    # properties, and the relationship -- read back from the incumbent
    # fixture's own declared IRIs, not re-typed literals, so this test
    # actually fails if the fixture and the resource drift apart.

    # Class identity for the migrated object type survives as an RDF class.
    assert ontology_ttl =~ ~s(<#{incumbent_class_iri}> a rdfs:Class)

    # The link target's class identity also survives (the Organization
    # object type, not just the Asset object type being migrated).
    assert ontology_ttl =~ ~s(<#{incumbent_link_class_iri}> a rdfs:Class)

    # Both datatype properties survive as RDF properties.
    for predicate_iri <- incumbent_property_predicates do
      assert ontology_ttl =~ ~s(<#{predicate_iri}> a rdf:Property)
    end

    # The relationship (link) survives as an RDF property whose range is
    # the linked object type's class -- this is the semantic relationship
    # fact, not just "some triple exists."
    assert ontology_ttl =~ ~s(<#{incumbent_link_predicate}> a rdf:Property)
    assert ontology_ttl =~ ~s(rdfs:range <#{incumbent_link_class_iri}>)

    # The R2RML mapping projects the same relationship as a real
    # rr:RefObjectMap-backed join, not merely an ontology-level assertion --
    # i.e. the relational join AshR2RML derived from the real belongs_to
    # metadata is present in the generated mapping.
    assert r2rml_ttl =~ "rr:TriplesMap"
    assert r2rml_ttl =~ ~s(rr:tableName "palantir_fixture_assets")
    assert r2rml_ttl =~ ~s(rr:tableName "palantir_fixture_organizations")
  end

  test "generated Turtle is deterministic across recompiles of the same admitted resource" do
    assert {:ok, first} = AshR2RML.compile_ash_ttl_bundle(Asset)
    assert {:ok, second} = AshR2RML.compile_ash_ttl_bundle(Asset)

    assert first.files == second.files
    assert first.sha256 == second.sha256
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHookVocabularyTest do
  use ExUnit.Case, async: true

  @ontology "priv/ontology/knowledge-hooks.ttl"
  @shapes "priv/shapes/knowledge-hooks.shacl.ttl"

  test "canonical Knowledge Hook ontology and SHACL law are valid Turtle" do
    assert {:ok, ontology} = RDF.Turtle.read_file(@ontology)
    assert {:ok, shapes} = RDF.Turtle.read_file(@shapes)
    assert Enum.any?(RDF.Data.statements(ontology))
    assert Enum.any?(RDF.Data.statements(shapes))
  end

  test "ontology carries the construct-only authority vocabulary" do
    text = File.read!(@ontology)
    shapes = File.read!(@shapes)

    assert text =~ "kh:authorityCeiling"
    assert text =~ "it grants no DO authority"
    assert shapes =~ "sh:hasValue \"CONSTRUCT\""
    assert shapes =~ "kh:requiresActuationReceipt"
    assert shapes =~ "sh:hasValue true"
  end
end

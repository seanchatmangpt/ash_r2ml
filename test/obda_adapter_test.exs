# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.AdapterTest do
  @moduledoc """
  Chicago-style: dispatches through `AshR2RML.OBDA.Adapter.dispatch/3` to the real
  `AshR2RML.OBDA.InMemory` engine against a real `Ash.DataLayer.Ets` resource -- no
  mocked collaborator. Ontop's own adapter config struct is exercised only for its
  pure `query/1`-options translation (`AshR2RML.OBDA.Ontop.command/1` already covers
  real-process execution in its own test suite); this suite does not re-invoke the
  real Ontop binary.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.GrandExample.{Domain, Organization}
  alias AshR2RML.OBDA.Adapter
  alias AshR2RML.OBDA.Adapter.{InMemoryConfig, OntopConfig}

  test "dispatch/3 routes to the real in-memory engine via engine_name/0" do
    assert InMemoryConfig.engine_name() == :in_memory
    assert OntopConfig.engine_name() == :ontop
  end

  test "dispatch/3 queries a real Ash.DataLayer.Ets resource through InMemoryConfig" do
    {:ok, mapping} = AshR2RML.Resource.Info.mapping_result(Organization)

    org =
      Organization
      |> Ash.Changeset.for_create(:create, %{name: "Adapter Co", version: "1.0.0"}, domain: Domain)
      |> Ash.create!(domain: Domain)

    config = %InMemoryConfig{specs: [{Organization, mapping}], read_opts: [domain: Domain]}

    assert {:ok, observation} =
             Adapter.dispatch(config, "SELECT ?s WHERE { ?s a <https://schema.org/Organization> }")

    assert %{"s" => "https://schema.org/Organization/#{org.id}"} in observation.rows
  end

  test "OntopConfig.query/3 builds real Ontop CLI options and refuses without a mapping" do
    config = %OntopConfig{db_url: "jdbc:postgresql://localhost/db"}

    assert {:error, %AshR2RML.OBDA.Observation{refusal: refusal}} =
             Adapter.dispatch(config, "SELECT * WHERE { ?s ?p ?o }", query_path: "/tmp/query.sparql")

    # :REFUSED_MISSING_MAPPING never existed in lib/; the real collaborator
    # (AshR2RML.OBDA.required/2) raises :REFUSED_OBDA_EXECUTION for missing
    # required Ontop options, including mapping_path. Same fix as 7f7f262,
    # which never landed on main.
    assert refusal.code == :REFUSED_OBDA_EXECUTION
  end
end

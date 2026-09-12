# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.SparqlParityTest do
  @moduledoc """
  Chicago-Style Multi-Engine SPARQL Differential Parity Comparator Test Suite.
  Adversarially compares direct in-memory SPARQL execution (via SPARQL.ex)
  against live virtual Ontop OBDA execution over PostgreSQL container `xaas-db-1`.
  Proves semantic equivalence with RDF term canonicalization.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDA.Ontop
  alias AshR2RML.SPARQL.{Differential, Local, Observation, Query, Result}

  @ontop_image "ontop/ontop:5.5.0"
  @tmp_dir Path.expand("tmp/adversarial_sparql_parity")
  @jdbc_jar Path.expand("priv/ontop/jdbc/postgresql-42.7.4.jar")

  @moduletag skip: AshR2RML.Test.DockerInfraCheck.skip_reason()

  setup_all do
    File.mkdir_p!(@tmp_dir)

    # 1. Seed PostgreSQL database in xaas-db-1 container
    System.cmd("docker", [
      "exec",
      "xaas-db-1",
      "psql",
      "-U",
      "postgres",
      "-d",
      "postgres",
      "-c",
      """
      DROP TABLE IF EXISTS adv_parity_tasks CASCADE;
      DROP TABLE IF EXISTS adv_parity_projects CASCADE;

      CREATE TABLE adv_parity_projects (
        id VARCHAR(32) PRIMARY KEY,
        title VARCHAR(200) NOT NULL,
        budget NUMERIC(12, 2) NOT NULL,
        active BOOLEAN NOT NULL,
        description TEXT
      );

      CREATE TABLE adv_parity_tasks (
        id VARCHAR(32) PRIMARY KEY,
        project_id VARCHAR(32) NOT NULL,
        name VARCHAR(200) NOT NULL,
        priority INTEGER NOT NULL,
        hours NUMERIC(6, 2) NOT NULL,
        completed_at TIMESTAMP,
        FOREIGN KEY (project_id) REFERENCES adv_parity_projects(id)
      );

      INSERT INTO adv_parity_projects (id, title, budget, active, description) VALUES
        ('proj_alpha', 'Alpha Core', 50000.00, true, 'Core Engine Development'),
        ('proj_beta', 'Beta Edge', 20000.00, true, NULL),
        ('proj_gamma', 'Gamma Sunset', 10000.00, false, 'Legacy Decommission');

      INSERT INTO adv_parity_tasks (id, project_id, name, priority, hours, completed_at) VALUES
        ('task_1', 'proj_alpha', 'Differential Engine', 1, 45.50, '2026-08-21 10:00:00'),
        ('task_2', 'proj_alpha', 'RDF Canonicalizer', 2, 30.00, NULL),
        ('task_3', 'proj_beta', 'Edge Sync', 1, 15.25, '2026-08-20 18:00:00'),
        ('task_4', 'proj_gamma', 'Donor Cleanup', 3, 8.00, '2026-08-19 12:00:00');
      """
    ])

    # 2. Write R2RML Mapping
    mapping_ttl = """
    @prefix rr: <http://www.w3.org/ns/r2rml#> .
    @prefix ex: <https://example.org/differential#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    <#ProjectMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "adv_parity_projects" ] ;
      rr:subjectMap [
        rr:template "https://example.org/project/{id}" ;
        rr:class ex:Project
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:title ;
        rr:objectMap [ rr:column "title"; rr:datatype xsd:string ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:budget ;
        rr:objectMap [ rr:column "budget"; rr:datatype xsd:decimal ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:active ;
        rr:objectMap [ rr:column "active"; rr:datatype xsd:boolean ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:description ;
        rr:objectMap [ rr:column "description"; rr:datatype xsd:string ]
      ] .

    <#TaskMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "adv_parity_tasks" ] ;
      rr:subjectMap [
        rr:template "https://example.org/task/{id}" ;
        rr:class ex:Task
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:name ;
        rr:objectMap [ rr:column "name"; rr:datatype xsd:string ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:priority ;
        rr:objectMap [ rr:column "priority"; rr:datatype xsd:integer ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:hours ;
        rr:objectMap [ rr:column "hours"; rr:datatype xsd:decimal ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:completedAt ;
        rr:objectMap [ rr:column "completed_at"; rr:datatype xsd:dateTime ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:hasProject ;
        rr:objectMap [
          rr:parentTriplesMap <#ProjectMap> ;
          rr:joinCondition [
            rr:child "project_id" ;
            rr:parent "id"
          ]
        ]
      ] .
    """

    File.write!(Path.join(@tmp_dir, "parity_mapping.ttl"), mapping_ttl)

    password = resolve_postgres_password()

    # 3. Ontop properties
    props = """
    jdbc.url=jdbc:postgresql://xaas-db-1:5432/postgres
    jdbc.user=postgres
    jdbc.password=#{password}
    jdbc.driver=org.postgresql.Driver
    """

    File.write!(Path.join(@tmp_dir, "parity.properties"), props)
    :ok
  end

  defp resolve_postgres_password() do
    case System.get_env("POSTGRES_PASSWORD") || System.get_env("PGPASSWORD") do
      nil ->
        case System.cmd("docker", ["exec", "xaas-db-1", "cat", "/run/secrets/postgrespassword"], stderr_to_stdout: true) do
          {pass, 0} -> String.trim(pass)
          _ -> "postgres"
        end

      pass ->
        pass
    end
  end

  defp build_local_rdf_graph do
    alias RDF.{IRI, Literal}
    alias RDF.NS.XSD

    rdf_type = IRI.new("http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
    ex_project = IRI.new("https://example.org/differential#Project")
    ex_task = IRI.new("https://example.org/differential#Task")
    p_title = IRI.new("https://example.org/differential#title")
    p_budget = IRI.new("https://example.org/differential#budget")
    p_active = IRI.new("https://example.org/differential#active")
    p_desc = IRI.new("https://example.org/differential#description")
    p_name = IRI.new("https://example.org/differential#name")
    p_priority = IRI.new("https://example.org/differential#priority")
    p_hours = IRI.new("https://example.org/differential#hours")
    p_completed_at = IRI.new("https://example.org/differential#completedAt")
    p_has_project = IRI.new("https://example.org/differential#hasProject")

    proj_alpha = IRI.new("https://example.org/project/proj_alpha")
    proj_beta = IRI.new("https://example.org/project/proj_beta")
    proj_gamma = IRI.new("https://example.org/project/proj_gamma")

    task_1 = IRI.new("https://example.org/task/task_1")
    task_2 = IRI.new("https://example.org/task/task_2")
    task_3 = IRI.new("https://example.org/task/task_3")
    task_4 = IRI.new("https://example.org/task/task_4")

    triples = [
      # Projects
      {proj_alpha, rdf_type, ex_project},
      {proj_alpha, p_title, Literal.new("Alpha Core")},
      {proj_alpha, p_budget, Literal.new("50000.00", datatype: XSD.decimal())},
      {proj_alpha, p_active, Literal.new(true)},
      {proj_alpha, p_desc, Literal.new("Core Engine Development")},
      {proj_beta, rdf_type, ex_project},
      {proj_beta, p_title, Literal.new("Beta Edge")},
      {proj_beta, p_budget, Literal.new("20000.00", datatype: XSD.decimal())},
      {proj_beta, p_active, Literal.new(true)},
      {proj_gamma, rdf_type, ex_project},
      {proj_gamma, p_title, Literal.new("Gamma Sunset")},
      {proj_gamma, p_budget, Literal.new("10000.00", datatype: XSD.decimal())},
      {proj_gamma, p_active, Literal.new(false)},
      {proj_gamma, p_desc, Literal.new("Legacy Decommission")},

      # Tasks
      {task_1, rdf_type, ex_task},
      {task_1, p_name, Literal.new("Differential Engine")},
      {task_1, p_priority, Literal.new(1)},
      {task_1, p_hours, Literal.new("45.50", datatype: XSD.decimal())},
      {task_1, p_completed_at, Literal.new("2026-08-21T10:00:00", datatype: XSD.dateTime())},
      {task_1, p_has_project, proj_alpha},
      {task_2, rdf_type, ex_task},
      {task_2, p_name, Literal.new("RDF Canonicalizer")},
      {task_2, p_priority, Literal.new(2)},
      {task_2, p_hours, Literal.new("30.00", datatype: XSD.decimal())},
      {task_2, p_has_project, proj_alpha},
      {task_3, rdf_type, ex_task},
      {task_3, p_name, Literal.new("Edge Sync")},
      {task_3, p_priority, Literal.new(1)},
      {task_3, p_hours, Literal.new("15.25", datatype: XSD.decimal())},
      {task_3, p_completed_at, Literal.new("2026-08-20T18:00:00", datatype: XSD.dateTime())},
      {task_3, p_has_project, proj_beta},
      {task_4, rdf_type, ex_task},
      {task_4, p_name, Literal.new("Donor Cleanup")},
      {task_4, p_priority, Literal.new(3)},
      {task_4, p_hours, Literal.new("8.00", datatype: XSD.decimal())},
      {task_4, p_completed_at, Literal.new("2026-08-19T12:00:00", datatype: XSD.dateTime())},
      {task_4, p_has_project, proj_gamma}
    ]

    RDF.Graph.new(triples)
  end

  defp observe_ontop(query_str, query_name) do
    query_file = Path.join(@tmp_dir, query_name)
    File.write!(query_file, query_str)

    opts = [
      binary: "docker",
      prefix_args: [
        "run",
        "--rm",
        "--network",
        "xaas_default",
        "-v",
        "#{@tmp_dir}:/workspace",
        "-v",
        "#{@jdbc_jar}:/opt/ontop/lib/postgresql-42.7.4.jar",
        "--workdir",
        "/workspace",
        "--entrypoint",
        "/opt/ontop/ontop",
        @ontop_image
      ],
      mapping_path: "parity_mapping.ttl",
      properties_path: "parity.properties",
      query_path: query_name
    ]

    {:ok, admitted} = Query.admit(query_str)
    {:ok, ontop_obs} = Ontop.query(opts)

    %Observation{
      strategy: :ontop_cli,
      query_sha256: admitted.sha256,
      query_form: admitted.form,
      status: ontop_obs.status,
      standing: ontop_obs.standing,
      evidence_kind: ontop_obs.evidence_kind,
      result_kind: :bindings,
      result_sha256: Result.hash_rows(ontop_obs.rows),
      rows: ontop_obs.rows,
      metadata: %{engine: :ontop}
    }
  end

  describe "Multi-Engine SPARQL Differential Parity Verification" do
    test "proves exact multiset result parity for complex joins and filters across engines" do
      query = """
      PREFIX ex: <https://example.org/differential#>
      SELECT ?taskName ?hours ?projectTitle WHERE {
        ?project a ex:Project ;
                 ex:active true ;
                 ex:title ?projectTitle .
        ?task a ex:Task ;
              ex:hasProject ?project ;
              ex:name ?taskName ;
              ex:hours ?hours .
        FILTER (?hours >= 20.0)
      }
      """

      local_graph = build_local_rdf_graph()
      assert {:ok, local_obs} = Local.query(local_graph, query)
      assert length(local_obs.rows) == 2

      ontop_obs = observe_ontop(query, "parity_filter.rq")
      assert length(ontop_obs.rows) == 2

      # Compare both execution topologies via SPARQL Differential
      assert {:ok, receipt} =
               Differential.compare(:task_filter_differential, [local_obs, ontop_obs], %{
                 test: "filter_and_join"
               })

      assert receipt.verified? == true
      assert receipt.strategies == [:local_rdf, :ontop_cli]
      assert :ok = Differential.require_strategies(receipt, [:local_rdf, :ontop_cli])
      assert receipt.row_count_by_strategy == %{local_rdf: 2, ontop_cli: 2}
      assert receipt.result_sha256_by_strategy.local_rdf == receipt.result_sha256_by_strategy.ontop_cli
    end

    test "proves exact parity on OPTIONAL graph patterns and unbound nullable variables" do
      query = """
      PREFIX ex: <https://example.org/differential#>
      SELECT ?taskName ?desc WHERE {
        ?task a ex:Task ;
              ex:hasProject ?project ;
              ex:name ?taskName .
        OPTIONAL { ?project ex:description ?desc }
      }
      """

      local_graph = build_local_rdf_graph()
      assert {:ok, local_obs} = Local.query(local_graph, query)
      assert length(local_obs.rows) == 4

      ontop_obs = observe_ontop(query, "parity_optional.rq")
      assert length(ontop_obs.rows) == 4

      assert {:ok, receipt} =
               Differential.compare(:optional_differential, [local_obs, ontop_obs], %{
                 test: "optional_description"
               })

      assert receipt.verified? == true
      assert :ok = Differential.require_strategies(receipt, [:local_rdf, :ontop_cli])
      assert receipt.result_sha256_by_strategy.local_rdf == receipt.result_sha256_by_strategy.ontop_cli
    end
  end

  describe "Adversarial Differential Falsifiers & Typed Refusals" do
    test "refuses differential when one engine returns corrupted or mutated data" do
      query = """
      PREFIX ex: <https://example.org/differential#>
      SELECT ?taskName WHERE {
        ?task a ex:Task ;
              ex:name ?taskName .
      }
      """

      local_graph = build_local_rdf_graph()
      assert {:ok, local_obs} = Local.query(local_graph, query)

      corrupted_rows = [%{"taskName" => "Injected Corrupted Task"}]
      corrupted_obs = %{local_obs | strategy: :ontop_cli, rows: corrupted_rows}

      assert {:ok, receipt} =
               Differential.compare(:corrupted_test, [local_obs, corrupted_obs])

      refute receipt.verified?
      assert {:error, refusal} = Differential.require_strategies(receipt, [:local_rdf, :ontop_cli])
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    end

    test "refuses when differential contains fewer than two distinct strategies" do
      query = "SELECT ?x WHERE { ?x ?p ?o }"
      {:ok, admitted} = Query.admit(query)

      obs = %Observation{
        strategy: :local_rdf,
        query_sha256: admitted.sha256,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed,
        evidence_kind: :in_memory_execution,
        rows: []
      }

      assert {:error, refusal} = Differential.compare(:single_strategy, [obs])
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
    end

    test "refuses when observations were produced from different query strings" do
      query1 = "SELECT ?x WHERE { ?x ?p ?o }"
      query2 = "SELECT ?y WHERE { ?y ?p ?o }"
      {:ok, adm1} = Query.admit(query1)
      {:ok, adm2} = Query.admit(query2)

      obs1 = %Observation{
        strategy: :local_rdf,
        query_sha256: adm1.sha256,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed,
        evidence_kind: :in_memory_execution,
        rows: []
      }

      obs2 = %Observation{
        strategy: :ontop_cli,
        query_sha256: adm2.sha256,
        query_form: :select,
        status: :PARTIAL_ALIVE,
        standing: :observed,
        evidence_kind: :system_process,
        rows: []
      }

      assert {:error, refusal} = Differential.compare(:mixed_queries, [obs1, obs2])
      assert refusal.code == :REFUSED_UNPROVEN_EQUIVALENCE
      assert length(refusal.evidence.query_sha256s) == 2
    end
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.OntopPostgresTest do
  @moduledoc """
  Chicago-Style Live Ontop OBDA adversarial test suite.
  Zero mocking of core boundaries:
  - Real PostgreSQL container (`xaas-db-1`)
  - Real `ontop/ontop:5.5.0` in Docker on network `xaas_default`
  - Real PostgreSQL JDBC driver (`priv/ontop/jdbc/postgresql-42.7.4.jar`)
  - Real W3C R2RML multi-column joins, nullables, FILTER, OPTIONAL, ORDER BY, and datatypes.
  """
  use ExUnit.Case, async: false

  alias AshR2RML.OBDA.Ontop

  @ontop_image "ontop/ontop:5.5.0"
  @tmp_dir Path.expand("tmp/adversarial_ontop_postgres")
  @jdbc_jar Path.expand("priv/ontop/jdbc/postgresql-42.7.4.jar")

  @moduletag skip: AshR2RML.Test.DockerInfraCheck.skip_reason()

  setup_all do
    File.mkdir_p!(@tmp_dir)

    # Seed PostgreSQL schema and data in xaas-db-1 container
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
      DROP TABLE IF EXISTS adv_tasks CASCADE;
      DROP TABLE IF EXISTS adv_projects CASCADE;
      DROP TABLE IF EXISTS adv_tenants CASCADE;

      CREATE TABLE adv_tenants (
        id VARCHAR(32) PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        created_at TIMESTAMP NOT NULL
      );

      CREATE TABLE adv_projects (
        tenant_id VARCHAR(32) NOT NULL,
        project_id VARCHAR(32) NOT NULL,
        title VARCHAR(200) NOT NULL,
        budget NUMERIC(12, 2) NOT NULL,
        active BOOLEAN NOT NULL,
        description TEXT,
        PRIMARY KEY(tenant_id, project_id),
        FOREIGN KEY (tenant_id) REFERENCES adv_tenants(id)
      );

      CREATE TABLE adv_tasks (
        tenant_id VARCHAR(32) NOT NULL,
        project_id VARCHAR(32) NOT NULL,
        task_id VARCHAR(32) NOT NULL,
        name VARCHAR(200) NOT NULL,
        priority INTEGER NOT NULL,
        hours NUMERIC(6, 2) NOT NULL,
        completed_at TIMESTAMP,
        PRIMARY KEY(tenant_id, project_id, task_id),
        FOREIGN KEY (tenant_id, project_id) REFERENCES adv_projects(tenant_id, project_id)
      );

      INSERT INTO adv_tenants (id, name, created_at) VALUES
        ('t_alpha', 'Alpha Corp', '2026-01-15 10:00:00'),
        ('t_beta', 'Beta Labs', '2026-02-20 14:30:00');

      INSERT INTO adv_projects (tenant_id, project_id, title, budget, active, description) VALUES
        ('t_alpha', 'p_obda', 'Ontop OBDA Engine', 75000.50, true, 'Adversarial OBDA integration test suite'),
        ('t_alpha', 'p_legacy', 'Legacy Migration', 25000.00, false, NULL),
        ('t_beta', 'p_reactor', 'Reactor Pipeline', 120000.00, true, 'Causal workflow runtime');

      INSERT INTO adv_tasks (tenant_id, project_id, task_id, name, priority, hours, completed_at) VALUES
        ('t_alpha', 'p_obda', 'task_1', 'R2RML Join Mapping', 1, 40.50, '2026-08-21 12:00:00'),
        ('t_alpha', 'p_obda', 'task_2', 'Filter & Optional Testing', 2, 25.00, NULL),
        ('t_alpha', 'p_legacy', 'task_3', 'Deprecate Donor Code', 3, 10.00, '2026-08-20 09:15:00'),
        ('t_beta', 'p_reactor', 'task_4', 'Saga Compensation', 1, 55.75, NULL);
      """
    ])

    # Write R2RML mapping with multi-column joins, datatype conversions, and optional relationships
    mapping_ttl = """
    @prefix rr: <http://www.w3.org/ns/r2rml#> .
    @prefix ex: <https://example.org/adversarial#> .
    @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .

    <#TenantMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "adv_tenants" ] ;
      rr:subjectMap [
        rr:template "https://example.org/tenant/{id}" ;
        rr:class ex:Tenant
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:tenantId ;
        rr:objectMap [ rr:column "id"; rr:datatype xsd:string ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:name ;
        rr:objectMap [ rr:column "name"; rr:datatype xsd:string ]
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:createdAt ;
        rr:objectMap [ rr:column "created_at"; rr:datatype xsd:dateTime ]
      ] .

    <#ProjectMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "adv_projects" ] ;
      rr:subjectMap [
        rr:template "https://example.org/tenant/{tenant_id}/project/{project_id}" ;
        rr:class ex:Project
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:projectId ;
        rr:objectMap [ rr:column "project_id"; rr:datatype xsd:string ]
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
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:hasTenant ;
        rr:objectMap [
          rr:parentTriplesMap <#TenantMap> ;
          rr:joinCondition [
            rr:child "tenant_id" ;
            rr:parent "id"
          ]
        ]
      ] .

    <#TaskMap> a rr:TriplesMap ;
      rr:logicalTable [ rr:tableName "adv_tasks" ] ;
      rr:subjectMap [
        rr:template "https://example.org/tenant/{tenant_id}/project/{project_id}/task/{task_id}" ;
        rr:class ex:Task
      ] ;
      rr:predicateObjectMap [
        rr:predicate ex:taskId ;
        rr:objectMap [ rr:column "task_id"; rr:datatype xsd:string ]
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
            rr:child "tenant_id" ;
            rr:parent "tenant_id"
          ] ;
          rr:joinCondition [
            rr:child "project_id" ;
            rr:parent "project_id"
          ]
        ]
      ] .
    """

    File.write!(Path.join(@tmp_dir, "adversarial_mapping.ttl"), mapping_ttl)

    password = resolve_postgres_password()

    props = """
    jdbc.url=jdbc:postgresql://xaas-db-1:5432/postgres
    jdbc.user=postgres
    jdbc.password=#{password}
    jdbc.driver=org.postgresql.Driver
    """

    File.write!(Path.join(@tmp_dir, "adversarial.properties"), props)
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

  defp run_ontop_query(query_str, filename) do
    query_file = Path.join(@tmp_dir, filename)
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
      mapping_path: "adversarial_mapping.ttl",
      properties_path: "adversarial.properties",
      query_path: filename
    ]

    Ontop.query(opts)
  end

  describe "Real Ontop OBDA Multi-Column Joins" do
    test "executes compound key multi-column join across tasks and projects" do
      query = """
      PREFIX ex: <https://example.org/adversarial#>
      SELECT ?task ?taskName ?project ?projectTitle WHERE {
        ?task a ex:Task ;
              ex:name ?taskName ;
              ex:hasProject ?project .
        ?project a ex:Project ;
                 ex:title ?projectTitle .
      } ORDER BY ?taskName
      """

      assert {:ok, obs} = run_ontop_query(query, "multi_join.rq")
      assert obs.exit_status == 0
      assert obs.evidence_kind == :system_process
      assert length(obs.rows) == 4

      task_map = Map.new(obs.rows, fn row -> {row["taskName"], row["projectTitle"]} end)
      assert task_map["R2RML Join Mapping"] == "Ontop OBDA Engine"
      assert task_map["Filter & Optional Testing"] == "Ontop OBDA Engine"
      assert task_map["Deprecate Donor Code"] == "Legacy Migration"
      assert task_map["Saga Compensation"] == "Reactor Pipeline"
    end
  end

  describe "Real Ontop OBDA Nullables & OPTIONAL" do
    test "handles nullable description and completedAt correctly with OPTIONAL patterns" do
      query = """
      PREFIX ex: <https://example.org/adversarial#>
      SELECT ?projectTitle ?desc ?taskName ?completedAt WHERE {
        ?project a ex:Project ;
                 ex:title ?projectTitle .
        OPTIONAL { ?project ex:description ?desc }
        ?task ex:hasProject ?project ;
              ex:name ?taskName .
        OPTIONAL { ?task ex:completedAt ?completedAt }
      } ORDER BY ?projectTitle ?taskName
      """

      assert {:ok, obs} = run_ontop_query(query, "nullables_optional.rq")
      assert obs.exit_status == 0
      assert length(obs.rows) == 4

      # Find legacy task row where description is NULL
      legacy_row = Enum.find(obs.rows, &(&1["taskName"] == "Deprecate Donor Code"))
      assert legacy_row != nil
      assert legacy_row["projectTitle"] == "Legacy Migration"
      assert legacy_row["desc"] in ["", nil]
      assert legacy_row["completedAt"] != "" and legacy_row["completedAt"] != nil

      # Find task 2 where completedAt is NULL
      task2_row = Enum.find(obs.rows, &(&1["taskName"] == "Filter & Optional Testing"))
      assert task2_row != nil
      assert task2_row["desc"] == "Adversarial OBDA integration test suite"
      assert task2_row["completedAt"] in ["", nil]
    end
  end

  describe "Real Ontop OBDA FILTER, ORDER BY, and Datatype Conversions" do
    test "executes numeric/boolean FILTER with strict ORDER BY and datatypes" do
      query = """
      PREFIX ex: <https://example.org/adversarial#>
      PREFIX xsd: <http://www.w3.org/2001/XMLSchema#>
      SELECT ?taskName ?priority ?hours ?projectTitle WHERE {
        ?project a ex:Project ;
                 ex:active true ;
                 ex:title ?projectTitle .
        ?task ex:hasProject ?project ;
              ex:name ?taskName ;
              ex:priority ?priority ;
              ex:hours ?hours .
        FILTER (?priority >= 1 && ?hours >= 25.0)
      } ORDER BY DESC(?hours)
      """

      assert {:ok, obs} = run_ontop_query(query, "filter_order.rq")
      assert obs.exit_status == 0

      # Active projects with priority >= 1 and hours >= 25.0:
      # task_4 (55.75 hrs), task_1 (40.50 hrs), task_2 (25.00 hrs). (task_3 is on inactive project)
      assert length(obs.rows) == 3

      hours_list = Enum.map(obs.rows, & &1["hours"])
      task_names = Enum.map(obs.rows, & &1["taskName"])

      assert task_names == ["Saga Compensation", "R2RML Join Mapping", "Filter & Optional Testing"]
      assert Enum.at(hours_list, 0) =~ "55.75"
      assert Enum.at(hours_list, 1) =~ "40.5"
      assert Enum.at(hours_list, 2) =~ "25.0"
    end
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real bounded crown:
# - Turtle/SHACL and JSON-LD/SHACL converge on one mapping
# - generated PostgreSQL + R2RML executes through Ontop CLI
# - the same admitted query executes through SPARQL.Client against Ontop HTTP
# - SPARQL.ex executes an equivalent query over a local RDF.ex control graph
# - Neo4j remains the inherited control graph
# Technical parity never grants cutover authority.

defmodule AshR2RML.ObdaCrown do
  @workspace "tmp/ash_r2rml_obda"
  @postgres_db "ash_r2rml"
  @postgres_user "postgres"
  @postgres_password System.get_env("POSTGRES_PASSWORD") || System.get_env("PGPASSWORD") || "postgres"
  @neo4j_url "http://127.0.0.1:7474/db/neo4j/tx/commit"
  @ontop_image "ontop/ontop:5.5.0"
  @ontop_container "ash-r2ml-ontop-endpoint"
  @ontop_endpoint "http://127.0.0.1:8080/sparql"

  @profile """
  @prefix sh: <http://www.w3.org/ns/shacl#> .
  @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
  @prefix ex: <https://example.com/ontology/> .
  @prefix shapes: <https://example.com/shapes/> .
  @prefix r2ml: <https://seanchatmangpt.github.io/ash_r2rml#> .

  shapes:OrganizationShape
      a sh:NodeShape ;
      sh:targetClass ex:Organization ;
      r2ml:ashModule "Obda.Organization" ;
      r2ml:tableName "organizations" ;
      r2ml:subjectTemplate "https://example.com/id/organization/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] .

  shapes:AccountShape
      a sh:NodeShape ;
      sh:targetClass ex:Account ;
      r2ml:ashModule "Obda.Account" ;
      r2ml:tableName "accounts" ;
      r2ml:subjectTemplate "https://example.com/id/account/{id}" ;
      r2ml:identity [
          r2ml:identityName "primary" ;
          r2ml:identityKey "id" ;
          r2ml:primaryIdentity true
      ] ;
      sh:property [
          sh:path ex:id ;
          r2ml:ashName "id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:organizationId ;
          r2ml:ashName "organization_id" ;
          r2ml:postgresType "TEXT" ;
          sh:datatype xsd:string ;
          sh:minCount 1 ;
          sh:maxCount 1
      ] ;
      sh:property [
          sh:path ex:memberOf ;
          r2ml:ashName "organization" ;
          sh:class ex:Organization ;
          sh:minCount 1 ;
          sh:maxCount 1 ;
          r2ml:storageStrategy "foreign_key" ;
          r2ml:sourceKey "organization_id" ;
          r2ml:destinationKey "id"
      ] .
  """

  @sparql """
  PREFIX ex: <https://example.com/ontology/>
  SELECT ?account ?organization
  WHERE {
    ?account ex:memberOf ?organization .
  }
  ORDER BY ?account
  """

  @local_sparql """
  PREFIX ex: <https://example.com/ontology/>
  SELECT ?account ?organization
  WHERE {
    ?account ex:memberOf ?organization .
  }
  """

  @sql """
  SELECT
    'https://example.com/id/account/' || id AS account,
    'https://example.com/id/organization/' || organization_id AS organization
  FROM accounts
  ORDER BY account
  """

  @neo4j_query """
  MATCH (account:Account)-[:MEMBER_OF]->(organization:Organization)
  RETURN account.iri AS account, organization.iri AS organization
  ORDER BY account
  """

  def run! do
    jdbc_evidence = verify_pgjdbc!()

    File.rm_rf!(@workspace)
    File.mkdir_p!(@workspace)

    {:ok, admitted_query} = AshR2RML.admit_sparql(@sparql)
    unless admitted_query.form == :select, do: raise("SPARQL.ex did not admit crown SELECT query")

    ontology_hash = sha256(@profile)

    # The public ontology-first API intentionally returns the canonical mapping
    # bundle. The full compiler produces additional executable projections and
    # a receipt from the same admitted profile. Verify those two boundaries are
    # identical instead of assuming the public bundle is a Compilation struct.
    {:ok, turtle_bundle} = AshR2RML.compile_turtle(@profile, ontology_hash: ontology_hash)
    {:ok, turtle_r2rml} = AshR2RML.R2RML.render(turtle_bundle)
    {:ok, profile} = AshR2RML.ingest_turtle(@profile, ontology_hash: ontology_hash)
    {:ok, compilation} = AshR2RML.Compiler.compile(profile)

    unless compilation.mapping_bundle == turtle_bundle,
      do: raise("public Turtle bundle diverged from full ontology-first compilation")

    unless compilation.r2rml == turtle_r2rml,
      do: raise("Turtle mapping bundle renderer diverged from full compilation")

    # The exact same RDF/SHACL subject must survive a JSON-LD serialization round-trip.
    profile_graph = RDF.Turtle.read_string!(@profile)
    {:ok, profile_jsonld} = AshR2RML.JSONLD.encode_rdf(profile_graph, pretty: false)
    {:ok, jsonld_bundle} = AshR2RML.compile_jsonld(profile_jsonld, ontology_hash: ontology_hash)
    {:ok, jsonld_r2rml} = AshR2RML.R2RML.render(jsonld_bundle)

    unless jsonld_r2rml == compilation.r2rml,
      do: raise("Turtle/JSON-LD mapping manufacture diverged")

    {:ok, jsonld_ggen_bundle} =
      AshR2RML.Ggen.compile_jsonld_bundle(profile_jsonld, ontology_hash: ontology_hash)

    unless jsonld_ggen_bundle.files["priv/r2rml/mapping.ttl"] == compilation.r2rml,
      do: raise("ggen JSON-LD input path diverged from Turtle mapping manufacture")

    mapping_host = Path.expand(Path.join(@workspace, "mapping.ttl"))
    query_host = Path.expand(Path.join(@workspace, "query.rq"))
    properties_host = Path.expand(Path.join(@workspace, "postgres.properties"))

    File.write!(mapping_host, compilation.r2rml)
    File.write!(query_host, @sparql)

    File.write!(
      properties_host,
      """
      jdbc.url=jdbc:postgresql://127.0.0.1:5432/#{@postgres_db}
      jdbc.user=#{@postgres_user}
      jdbc.password=#{@postgres_password}
      jdbc.driver=org.postgresql.Driver
      """
    )

    reset_postgres!()
    psql_exec!(compilation.postgres_ddl)

    fixture_sql = """
    INSERT INTO organizations (id) VALUES ('org-1'), ('org-2');
    INSERT INTO accounts (id, organization_id) VALUES
      ('acct-1', 'org-1'),
      ('acct-2', 'org-1'),
      ('acct-3', 'org-2');
    """

    psql_exec!(fixture_sql)
    sql_rows = psql_query!(@sql)

    workspace = File.cwd!()
    container_root = "/workspace/" <> @workspace

    # Execution topology 1: official Ontop CLI process.
    {:ok, cli_observation} =
      AshR2RML.OBDA.Ontop.query(%{
        binary: "docker",
        prefix_args:
          ["run", "--rm"] ++
            ontop_docker_args(workspace, jdbc_evidence.directory) ++ [@ontop_image, "ontop"],
        mapping_path: container_root <> "/mapping.ttl",
        query_path: container_root <> "/query.rq",
        properties_path: container_root <> "/postgres.properties",
        mapping: compilation.r2rml,
        query: @sparql
      })

    unless cli_observation.evidence_kind == :system_process,
      do: raise("OBDA crown requires a real Ontop CLI process observation")

    fixture_sha256 = sha256(fixture_sql)

    cli_sql =
      AshR2RML.Parity.compare(
        :sparql_sql,
        :organization_account_cli,
        cli_observation.rows,
        sql_rows,
        %{
          left_system: :ontop_cli,
          right_system: :postgres,
          left_query: @sparql,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: cli_observation.mapping_sha256
        }
      )

    unless cli_sql.verified?, do: raise("Ontop CLI/PostgreSQL parity mismatch")

    # Execution topology 2: a live SPARQL 1.1 Protocol endpoint queried by SPARQL.Client.
    start_ontop_endpoint!(workspace, container_root, jdbc_evidence.directory)

    protocol_observation =
      try do
        {:ok, observation} =
          AshR2RML.SPARQL.Protocol.query(
            @ontop_endpoint,
            @sparql,
            request_method: :get,
            protocol_version: "1.1",
            result_format: :json
          )

        observation
      after
        stop_ontop_endpoint!()
      end

    unless protocol_observation.evidence_kind == :sparql_protocol,
      do: raise("SPARQL.Client crown requires a real protocol observation")

    protocol_sql =
      AshR2RML.Parity.compare(
        :sparql_sql,
        :organization_account_protocol,
        protocol_observation.rows,
        sql_rows,
        %{
          left_system: :sparql_client,
          right_system: :postgres,
          left_query: @sparql,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: cli_observation.mapping_sha256
        }
      )

    unless protocol_sql.verified?, do: raise("SPARQL.Client/PostgreSQL parity mismatch")

    unless protocol_observation.result_sha256 ==
             AshR2RML.SPARQL.Result.hash_rows(cli_observation.rows),
           do: raise("SPARQL.Client and Ontop CLI normalized result identities differ")

    # Execution topology 3: SPARQL.ex over a local RDF.ex graph describing the same fixture.
    local_graph = local_fixture_graph()
    {:ok, local_observation} = AshR2RML.SPARQL.Local.query(local_graph, @local_sparql)

    local_sql =
      AshR2RML.Parity.compare(
        :sparql_sql,
        :organization_account_local_rdf,
        local_observation.rows,
        sql_rows,
        %{
          left_system: :sparql_ex,
          right_system: :postgres,
          left_query: @local_sparql,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: cli_observation.mapping_sha256
        }
      )

    unless local_sql.verified?, do: raise("SPARQL.ex local RDF/PostgreSQL semantic mismatch")

    # Execution topology 4: inherited Neo4j control graph.
    seed_neo4j!()
    neo4j_rows = neo4j_query!(@neo4j_query)

    neo4j_postgres =
      AshR2RML.Parity.compare(
        :neo4j_postgres,
        :organization_account,
        neo4j_rows,
        sql_rows,
        %{
          left_system: :neo4j,
          right_system: :postgres,
          left_query: @neo4j_query,
          right_query: @sql,
          fixture_sha256: fixture_sha256,
          mapping_sha256: cli_observation.mapping_sha256
        }
      )

    unless neo4j_postgres.verified?, do: raise("Neo4j/PostgreSQL parity mismatch")

    technical_receipt =
      compilation.receipt
      |> AshR2RML.Compiler.attach_parity_witness(:sparql_sql, Map.from_struct(protocol_sql))
      |> AshR2RML.Compiler.attach_parity_witness(
        :neo4j_postgres,
        Map.from_struct(neo4j_postgres)
      )

    unless technical_receipt.query_parity == :VERIFIED,
      do: raise("SPARQL/SQL witness was not admitted")

    unless technical_receipt.neo4j_postgres_parity == :VERIFIED,
      do: raise("Neo4j/Postgres witness was not admitted")

    if AshR2RML.Compiler.cutover_ready?(technical_receipt),
      do: raise("technical parity must not manufacture cutover authority")

    File.write!(
      Path.join(@workspace, "parity-receipt.json"),
      Jason.encode!(
        json_term(%{
          status: :PARTIAL_ALIVE,
          standing: :bounded_multi_engine_semantic_parity,
          serialization_parity: %{
            turtle_r2rml_sha256: sha256(compilation.r2rml),
            jsonld_r2rml_sha256: sha256(jsonld_r2rml),
            verified?: jsonld_r2rml == compilation.r2rml
          },
          sparql_ex_local_sql: local_sql,
          ontop_cli_sql: cli_sql,
          sparql_client_sql: protocol_sql,
          neo4j_postgres: neo4j_postgres,
          external_dependencies: %{
            ontop_image: @ontop_image,
            pgjdbc: %{
              artifact: jdbc_evidence.artifact,
              sha256: jdbc_evidence.sha256
            }
          },
          compilation_receipt: technical_receipt
        }),
        pretty: true
      )
    )

    IO.puts("ALIVE bounded corpus: Turtle/JSON-LD + SPARQL.ex/SPARQL.Client/Ontop + Postgres/Neo4j parity")
  end

  defp local_fixture_graph do
    member_of = RDF.iri("https://example.com/ontology/memberOf")

    RDF.Graph.new([
      {RDF.iri("https://example.com/id/account/acct-1"), member_of,
       RDF.iri("https://example.com/id/organization/org-1")},
      {RDF.iri("https://example.com/id/account/acct-2"), member_of,
       RDF.iri("https://example.com/id/organization/org-1")},
      {RDF.iri("https://example.com/id/account/acct-3"), member_of,
       RDF.iri("https://example.com/id/organization/org-2")}
    ])
  end

  defp start_ontop_endpoint!(workspace, container_root, jdbc_directory) do
    stop_ontop_endpoint!()

    {_container_id, 0} =
      System.cmd(
        "docker",
        ["run", "-d", "--rm", "--name", @ontop_container] ++
          ontop_docker_args(workspace, jdbc_directory) ++
          [
            @ontop_image,
            "ontop",
            "endpoint",
            "-m",
            container_root <> "/mapping.ttl",
            "-p",
            container_root <> "/postgres.properties"
          ],
        stderr_to_stdout: true
      )

    wait_for_endpoint!(60)
  end

  defp ontop_docker_args(workspace, jdbc_directory) do
    [
      "--network",
      "host",
      "-e",
      "ONTOP_LOG_LEVEL=ERROR",
      "-v",
      "#{workspace}:/workspace:ro",
      "-v",
      "#{jdbc_directory}:/opt/ontop/jdbc:ro"
    ]
  end

  defp verify_pgjdbc! do
    directory =
      System.get_env("ASH_R2RML_ONTOP_JDBC_DIR") ||
        raise "ASH_R2RML_ONTOP_JDBC_DIR must point to the admitted Ontop JDBC directory"

    expected_sha256 =
      System.get_env("ASH_R2RML_PGJDBC_SHA256") ||
        raise "ASH_R2RML_PGJDBC_SHA256 must pin the admitted PostgreSQL JDBC artifact"

    jars = Path.wildcard(Path.join(directory, "postgresql-*.jar")) |> Enum.sort()

    jar =
      case jars do
        [single] ->
          single

        [] ->
          raise "Ontop JDBC directory contains no pinned PostgreSQL JDBC driver"

        many ->
          raise "Ontop JDBC directory must contain exactly one PostgreSQL JDBC driver, got #{inspect(many)}"
      end

    actual_sha256 = jar |> File.read!() |> sha256()

    unless actual_sha256 == String.downcase(expected_sha256) do
      raise "PostgreSQL JDBC digest mismatch: expected #{expected_sha256}, observed #{actual_sha256}"
    end

    %{
      directory: Path.expand(directory),
      artifact: Path.basename(jar),
      sha256: actual_sha256
    }
  end

  defp wait_for_endpoint!(0), do: raise("Ontop SPARQL endpoint did not become ready")

  defp wait_for_endpoint!(attempts) do
    case System.cmd(
           "curl",
           ["--fail", "--silent", "--show-error", "http://127.0.0.1:8080/"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        :ok

      _ ->
        Process.sleep(1_000)
        wait_for_endpoint!(attempts - 1)
    end
  end

  defp stop_ontop_endpoint! do
    _ = System.cmd("docker", ["rm", "-f", @ontop_container], stderr_to_stdout: true)
    :ok
  end

  defp reset_postgres! do
    psql_exec!("DROP TABLE IF EXISTS accounts, organizations CASCADE;")
  end

  defp psql_exec!(sql) do
    {_output, 0} =
      System.cmd(
        "psql",
        [
          "--no-psqlrc",
          "-v",
          "ON_ERROR_STOP=1",
          "-h",
          "127.0.0.1",
          "-U",
          @postgres_user,
          "-d",
          @postgres_db,
          "-c",
          sql
        ],
        env: [{"PGPASSWORD", @postgres_password}],
        stderr_to_stdout: true
      )

    :ok
  end

  defp psql_query!(sql) do
    {output, 0} =
      System.cmd(
        "psql",
        [
          "--csv",
          "--no-psqlrc",
          "-P",
          "footer=off",
          "-h",
          "127.0.0.1",
          "-U",
          @postgres_user,
          "-d",
          @postgres_db,
          "-c",
          sql
        ],
        env: [{"PGPASSWORD", @postgres_password}]
      )

    AshR2RML.OBDA.Ontop.parse_csv(output)
  end

  defp seed_neo4j! do
    cypher!("MATCH (n) DETACH DELETE n")

    cypher!("""
    CREATE (o1:Organization {id: 'org-1', iri: 'https://example.com/id/organization/org-1'}),
           (o2:Organization {id: 'org-2', iri: 'https://example.com/id/organization/org-2'}),
           (a1:Account {id: 'acct-1', iri: 'https://example.com/id/account/acct-1'}),
           (a2:Account {id: 'acct-2', iri: 'https://example.com/id/account/acct-2'}),
           (a3:Account {id: 'acct-3', iri: 'https://example.com/id/account/acct-3'}),
           (a1)-[:MEMBER_OF]->(o1),
           (a2)-[:MEMBER_OF]->(o1),
           (a3)-[:MEMBER_OF]->(o2)
    """)
  end

  defp neo4j_query!(statement) do
    response = cypher!(statement)
    result = response["results"] |> List.first()
    columns = result["columns"]

    Enum.map(result["data"], fn %{"row" => row} ->
      Map.new(Enum.zip(columns, row))
    end)
  end

  defp cypher!(statement) do
    payload = Jason.encode!(%{statements: [%{statement: statement, resultDataContents: ["row"]}]})

    {output, 0} =
      System.cmd(
        "curl",
        [
          "--fail-with-body",
          "--silent",
          "--show-error",
          "-u",
          "neo4j:password",
          "-H",
          "Content-Type: application/json",
          "-d",
          payload,
          @neo4j_url
        ],
        stderr_to_stdout: true
      )

    decoded = Jason.decode!(output)

    case decoded["errors"] do
      [] -> decoded
      errors -> raise "Neo4j control query failed: #{inspect(errors)}"
    end
  end

  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()

  defp json_term(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), json_term(value)} end)
  end

  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value), do: value

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

AshR2RML.ObdaCrown.run!()
# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.EightyTwentyCoverageTest do
  use ExUnit.Case, async: true

  alias AshR2RML.{
    Compiler,
    Compilation,
    CompilationReceipt,
    OBDA.Observation,
    OBDA.Ontop,
    Refusal,
    SemanticIR,
    SPARQL.Differential,
    SPARQL.DifferentialReceipt,
    SPARQL.Observation,
    SPARQL.Result
  }

  describe "AshR2RML.Compiler high-value unit contracts" do
    test "explore/1 delegates admission" do
      profile = %{
        class: "https://schema.org/Person",
        attributes: [
          %{name: :name, type: :string, predicate: "http://xmlns.com/foaf/0.1/name"}
        ]
      }

      assert {:ok, %SemanticIR{}} = Compiler.explore(profile)
    end

    test "cutover_ready?/1 enforces verified parity witnesses and cutover authority" do
      unready = %CompilationReceipt{
        query_parity: :UNKNOWN,
        cutover_authority: nil,
        blocked: [:sparql_sql_behavioral_parity]
      }

      refute Compiler.cutover_ready?(unready)

      ready = %CompilationReceipt{
        query_parity: :VERIFIED,
        cutover_authority: :AUTHORIZED,
        blocked: []
      }

      assert Compiler.cutover_ready?(ready)
    end

    test "attach_parity_witness/3 validates witness structure" do
      receipt = %CompilationReceipt{blocked: [:sparql_sql_behavioral_parity]}

      valid_witness = %{verified?: true, receipt_sha256: "abc123sha"}

      updated = Compiler.attach_parity_witness(receipt, :sparql_sql, valid_witness)
      assert updated.query_parity == :VERIFIED
      refute :sparql_sql_behavioral_parity in updated.blocked

      invalid_witness = %{verified?: false, receipt_sha256: nil}
      refused = Compiler.attach_parity_witness(receipt, :sparql_sql, invalid_witness)
      assert length(refused.refusals) == 1
      assert hd(refused.refusals).code == :REFUSED_UNPROVEN_EQUIVALENCE
    end

    test "authorize_cutover/2 updates receipt authority" do
      receipt = %CompilationReceipt{blocked: [:cutover_authority]}

      valid_auth = %{authorized?: true, receipt_sha256: "auth789sha"}

      updated = Compiler.authorize_cutover(receipt, valid_auth)
      assert updated.cutover_authority == :AUTHORIZED
      refute :cutover_authority in updated.blocked

      invalid_auth = %{authorized?: false}
      refused = Compiler.authorize_cutover(receipt, invalid_auth)
      assert length(refused.refusals) == 1
    end

    test "compile/1 with map profile returns compilation struct" do
      profile = %{
        class: "https://schema.org/Person",
        subject: %{template: "https://example.org/users/{id}"},
        attributes: [
          %{name: :id, type: :string, primary_key?: true},
          %{name: :name, type: :string, predicate: "http://xmlns.com/foaf/0.1/name"}
        ]
      }

      assert {:ok, %Compilation{} = compilation} = Compiler.compile(profile)
      assert compilation.status == :PARTIAL_ALIVE
      assert is_binary(compilation.r2rml)
    end
  end

  describe "AshR2RML.SPARQL.Differential" do
    test "compare/3 returns verified receipt when strategies match" do
      query_hash =
        :crypto.hash(:sha256, "SELECT ?s WHERE { ?s a <https://schema.org/Person> }") |> Base.encode16(case: :lower)

      rows = [%{"s" => "https://example.org/users/1"}]

      obs1 = %AshR2RML.SPARQL.Observation{
        strategy: :direct_sparql,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      }

      obs2 = %AshR2RML.SPARQL.Observation{
        strategy: :r2rml_obda,
        query_sha256: query_hash,
        query_form: :select,
        status: :ALIVE,
        standing: :observed,
        evidence_kind: :local_execution,
        rows: rows
      }

      assert {:ok, %DifferentialReceipt{} = receipt} =
               Differential.compare("UserSubject", [obs1, obs2], %{env: "test"})

      assert receipt.verified? == true
      assert length(receipt.strategies) == 2
      assert receipt.metadata == %{env: "test"}
    end

    test "compare/3 refuses empty or non-list observations" do
      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}} =
               Differential.compare("UserSubject", nil, %{})

      assert {:error, %Refusal{code: :REFUSED_UNPROVEN_EQUIVALENCE}} =
               Differential.compare("UserSubject", [], %{})
    end

    test "require_strategies/2 validates strategy list requirements" do
      receipt = %DifferentialReceipt{
        subject: "test",
        query_sha256: "q1",
        strategies: [:direct_sparql, :r2rml_obda],
        result_sha256_by_strategy: %{},
        verified?: true,
        receipt_sha256: "r1"
      }

      assert :ok == Differential.require_strategies(receipt, [:direct_sparql, :r2rml_obda])
      assert {:error, %Refusal{}} = Differential.require_strategies(receipt, [:direct_sparql, :missing_strat])
    end
  end

  describe "AshR2RML.OBDA.Ontop CLI runner & CSV parser" do
    test "command/1 generates valid CLI arguments" do
      opts = [
        mapping_path: "/path/to/mapping.ttl",
        query_path: "/path/to/query.rq",
        properties_path: "/path/to/ontop.properties",
        binary: "ontop"
      ]

      assert {:ok, {"ontop", args}} = Ontop.command(opts)
      assert "query" in args
      assert "-m" in args
      assert "/path/to/mapping.ttl" in args
    end

    test "parse_csv/1 correctly parses Ontop SELECT query output" do
      csv = """
      "person","name"
      "https://example.org/users/1","Alice"
      "https://example.org/users/2","Bob"
      """

      rows = Ontop.parse_csv(csv)
      assert length(rows) == 2
      assert Enum.at(rows, 0) == %{"person" => "https://example.org/users/1", "name" => "Alice"}
      assert Enum.at(rows, 1) == %{"person" => "https://example.org/users/2", "name" => "Bob"}
    end

    test "query/2 with test double runner executes injected function" do
      runner = fn "ontop", _args, _env ->
        {"""
         "person","name"
         "https://example.org/users/1","Alice"
         """, 0}
      end

      opts = [
        mapping_path: "/path/to/mapping.ttl",
        query_path: "/path/to/query.rq"
      ]

      assert {:ok, %AshR2RML.OBDA.Observation{} = obs} = Ontop.query(opts, runner)
      assert obs.evidence_kind == :injected_runner
      assert obs.exit_status == 0
      assert length(obs.rows) == 1
      assert Enum.at(obs.rows, 0)["name"] == "Alice"
    end
  end
end

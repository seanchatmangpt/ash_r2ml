# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Ggen do
  @moduledoc """
  ggen-facing deterministic compilation bundle.

  `AshR2RML` does not invoke ggen or write files. It manufactures a path/content
  graph plus an atomic publication plan so ggen can own rendering, filesystem
  actuation, migration versioning, replay, and receipts without independently
  reconstructing semantic decisions.

  Turtle and JSON-LD are alternate RDF input serializations. Both are admitted
  into the same normalized profile before manufacture so ggen never receives a
  serialization-specific semantic fork.

  Cloud ggen may also run in Ash-first mode. In that mode the maintained source
  is the Ash resource graph itself and `compile_ash_ttl_bundle/1` emits the
  ontology, operational SHACL shapes, and R2RML Turtle required by ggen.

  Semantic types use the same boundary: `compile_semantic_types_bundle/2`
  admits a content-addressed plan and returns deterministic generated artifacts.
  Runtime integration uses `compile_runtime_contract/1` to manufacture the exact-subject,
  authority-bound input consumed by the marketplace runtime integration pack.
  ggen still owns DO.

  GraphQL, when enabled, is a canonical read-only projection of the same admitted
  `SemanticIR`. It is never reconstructed from generated Ash source and never
  requires `ash_graphql`. The only GraphQL setting is `graphql: true | false`;
  custom application GraphQL belongs in `ash_graphql`.
  """

  alias AshR2RML.{Compilation, Manufacturing, Refusal}

  @spec compile_bundle(map(), keyword()) :: {:ok, map()} | {:error, Compilation.t() | Refusal.t() | term()}
  def compile_bundle(profile, opts \\ []) do
    with {:ok, dfcm} <- AshR2RML.DfCM.Compiler.compile(profile),
         compilation = dfcm.compilation,
         {:ok, receipt_json} <- encode_json(compilation.receipt),
         {:ok, integrity_json} <- encode_json(dfcm.integrity_receipt),
         {:ok, catalog_json} <- encode_json(compilation.ir),
         {:ok, graphql_files} <- graphql_files(compilation.ir, Keyword.get(opts, :graphql, false)) do
      files =
        %{
          "generated/ash/ontology_resources.ex" => compilation.ash_source,
          "generated/ecto/semantic_schema_migration.exs" => compilation.ecto_migration,
          "generated/sql/semantic_schema.sql" => compilation.postgres_ddl,
          "priv/r2rml/mapping.ttl" => compilation.r2rml,
          "generated/shacl/operational-profile.ttl" => compilation.shacl,
          "generated/catalog/resource-map.json" => catalog_json,
          "receipts/semantic-compilation.json" => receipt_json,
          "receipts/semantic-integrity.json" => integrity_json
        }
        |> Map.merge(graphql_files)

      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         receipt: compilation.receipt,
         integrity_receipt: dfcm.integrity_receipt,
         session_identity: dfcm.session_identity,
         proof_classes: dfcm.proof_classes,
         manufacturing_plan: Manufacturing.plan(files, dfcm.session_identity),
         files: files
       }}
    end
  end

  @doc "Verify hashes reported by ggen for an isolated stage before atomic publication."
  @spec verify_staged(map(), map()) ::
          {:ok, AshR2RML.Manufacturing.VerificationReceipt.t()} | {:error, AshR2RML.Refusal.t()}
  def verify_staged(%{manufacturing_plan: %AshR2RML.Manufacturing.Plan{} = plan}, observed_hashes)
      when is_map(observed_hashes) do
    Manufacturing.verify_staged(plan, observed_hashes)
  end

  @doc "Manufacture a deterministic ggen path/content graph from a semantic type profile."
  @spec compile_semantic_types_bundle(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_semantic_types_bundle(source, opts \\ []) do
    with {:ok, plan} <- AshR2RML.SemanticTypes.plan(source, opts),
         {:ok, files} <- AshR2RML.SemanticTypes.Generator.files(plan, opts),
         {:ok, receipt_json} <-
           encode_json(%{
             plan_id: plan.id,
             standing: :construct_only,
             status: :PARTIAL_ALIVE,
             providers: plan.providers,
             type_ids: Enum.map(plan.types, & &1.id)
           }) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         semantic_type_plan_id: plan.id,
         plan: plan,
         files: Map.put(files, "receipts/semantic-type-compilation.json", receipt_json <> "\n")
       }}
    end
  end

  @doc "Manufacture cloud-ggen TTL inputs directly from one or more Ash resources."
  @spec compile_ash_ttl_bundle(module() | [module()] | AshR2RML.Mapping.Bundle.t()) :: {:ok, map()} | {:error, term()}
  defdelegate compile_ash_ttl_bundle(resources_or_bundle), to: AshR2RML.Ggen.TTL, as: :emit

  @doc "Manufacture an exact-subject runtime integration contract for the GGen marketplace pack."
  @spec compile_runtime_contract(map()) :: {:ok, map()} | {:error, atom()}
  defdelegate compile_runtime_contract(input), to: AshR2RML.GgenRuntime, as: :contract

  @doc "Parse an RDF/SHACL Turtle profile, then manufacture the same deterministic ggen bundle."
  @spec compile_turtle_bundle(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_turtle_bundle(turtle, opts \\ []) do
    with :ok <- AshR2RML.Bounds.admit_input(turtle, opts),
         {:ok, profile} <- AshR2RML.Ingestion.from_turtle(turtle, opts) do
      compile_bundle(profile, Keyword.take(opts, [:graphql]))
    end
  end

  @doc "Parse a JSON-LD 1.1 RDF/SHACL profile, then manufacture the same deterministic ggen bundle."
  @spec compile_jsonld_bundle(String.t() | map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def compile_jsonld_bundle(jsonld, opts \\ []) do
    with :ok <- AshR2RML.Bounds.admit_input(jsonld, opts),
         {:ok, profile} <- AshR2RML.JSONLD.ingest(jsonld, opts) do
      compile_bundle(profile, Keyword.take(opts, [:graphql]))
    end
  end

  @doc """
  Manufacture deterministic API-adjacent projections from one admitted semantic IR.

  `graphql: true` adds a canonical read-only GraphQL SDL, semantic manifest, and
  projection receipt directly from `SemanticIR`. It does **not** add
  `AshGraphql.Resource`, GraphQL mutations, subscriptions, or any write authority
  to the generated Ash resource. `graphql: false` (the default) emits no GraphQL
  artifacts. Any non-boolean GraphQL value is refused; use `ash_graphql` when a
  custom GraphQL application surface is required.

  `json_api: true` retains the pre-existing AshJsonApi projection and is
  independent of the canonical GraphQL read plane.
  """
  @spec compile_api_bundle(map(), keyword()) :: {:ok, map()} | {:error, [Refusal.t()] | Refusal.t()}
  def compile_api_bundle(profile, opts \\ []) when is_map(profile) do
    graphql = Keyword.get(opts, :graphql, false)
    ash_opts = Keyword.delete(opts, :graphql)

    with {:ok, ir} <- AshR2RML.Admission.admit(profile),
         {:ok, ash_source} <- AshR2RML.Semantic.Ash.render(ir, ash_opts),
         {:ok, graphql_files} <- graphql_files(ir, graphql) do
      {:ok,
       %{
         status: :PARTIAL_ALIVE,
         standing: :construct_only,
         files: Map.put(graphql_files, "generated/ash/api_resources.ex", ash_source)
       }}
    end
  end

  defp graphql_files(ir, enabled) do
    case AshR2RML.Semantic.GraphQL.compile(ir, enabled) do
      {:ok, nil} ->
        {:ok, %{}}

      {:ok, projection} ->
        with {:ok, manifest_json} <- encode_json(projection.manifest),
             {:ok, receipt_json} <- encode_json(projection.receipt) do
          {:ok,
           %{
             "generated/graphql/schema.graphql" => projection.schema,
             "generated/graphql/semantic-manifest.json" => manifest_json <> "\n",
             "receipts/graphql-projection.json" => receipt_json <> "\n"
           }}
        end

      {:error, %Refusal{} = refusal} ->
        {:error, refusal}
    end
  end

  defp encode_json(value), do: value |> json_term() |> Jason.encode(pretty: true)
  defp json_term(%_{} = struct), do: struct |> Map.from_struct() |> json_term()
  defp json_term(map) when is_map(map), do: Map.new(map, fn {key, value} -> {json_key(key), json_term(value)} end)
  defp json_term(list) when is_list(list), do: Enum.map(list, &json_term/1)
  defp json_term(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&json_term/1)
  defp json_term(value) when value in [true, false, nil], do: value
  defp json_term(value) when is_atom(value), do: Atom.to_string(value)
  defp json_term(value) when is_binary(value) or is_number(value), do: value
  defp json_term(value), do: inspect(value)
  defp json_key({class_iri, relationship}), do: class_iri <> "#" <> to_string(relationship)
  defp json_key(key) when is_binary(key), do: key
  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: inspect(key)
end

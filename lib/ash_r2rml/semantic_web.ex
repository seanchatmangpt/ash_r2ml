# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.SPARQL.Query do
  @moduledoc """
  Admitted SPARQL query identity.

  Parsing is delegated to SPARQL.ex. The receipt identity covers the exact
  lexical query supplied by the caller; it is not a claim of canonical SPARQL
  algebra equivalence.
  """

  alias AshR2RML.Refusal

  @enforce_keys [:source, :parsed, :form, :sha256]
  defstruct [:source, :parsed, :form, :sha256]

  @type t :: %__MODULE__{
          source: String.t(),
          parsed: Elixir.SPARQL.Query.t(),
          form: atom(),
          sha256: String.t()
        }

  @spec load_file(String.t(), keyword()) :: {:ok, t()} | {:error, Refusal.t()}
  def load_file(file_path, _opts \\ []) when is_binary(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        admit(content)

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "failed to read SPARQL file from disk: #{inspect(reason)}",
           %{path: file_path}
         )}
    end
  end

  @spec admit(t() | String.t() | Elixir.SPARQL.Query.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit(%__MODULE__{} = admitted), do: {:ok, admitted}

  def admit(%Elixir.SPARQL.Query{query_string: source} = parsed) when is_binary(source) do
    {:ok,
     %__MODULE__{
       source: source,
       parsed: parsed,
       form: parsed.form,
       sha256: sha256(source)
     }}
  end

  def admit(source) when is_binary(source) do
    try do
      case Elixir.SPARQL.Query.new(source, default_prefixes: nil) do
        %Elixir.SPARQL.Query{} = parsed ->
          admit(parsed, source)

        {:error, reason} ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :sparql_query,
             "SPARQL.ex refused the query during language admission",
             %{reason: inspect(reason)}
           )}
      end
    rescue
      exception ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_query,
           "SPARQL.ex raised during language admission",
           %{reason: Exception.message(exception)}
         )}
    end
  end

  def admit(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_query,
       "expected SPARQL query text or SPARQL.Query",
       %{got: inspect(other)}
     )}
  end

  def admit(%Elixir.SPARQL.Query{} = parsed, source) when is_binary(source) do
    {:ok,
     %__MODULE__{
       source: source,
       parsed: parsed,
       form: parsed.form,
       sha256: sha256(source)
     }}
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

defmodule AshR2RML.SPARQL.Observation do
  @moduledoc "Evidence-bounded observation from one selected SPARQL execution strategy."

  @enforce_keys [:strategy, :query_sha256, :query_form, :status, :standing, :evidence_kind, :rows]
  defstruct [
    :strategy,
    :query_sha256,
    :query_form,
    :status,
    :standing,
    :evidence_kind,
    :endpoint,
    :result_kind,
    :result_sha256,
    rows: [],
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          strategy: :local_rdf | :protocol | :ontop_cli,
          query_sha256: String.t(),
          query_form: atom(),
          status: atom(),
          standing: atom(),
          evidence_kind: atom(),
          endpoint: String.t() | nil,
          result_kind: atom() | nil,
          result_sha256: String.t() | nil,
          rows: list(),
          metadata: map()
        }
end

defmodule AshR2RML.SPARQL.Result do
  @moduledoc "Normalizes RDF-Elixir SPARQL results into deterministic parity rows."

  alias AshR2RML.Refusal

  @spec normalize(term()) :: {:ok, atom(), list()} | {:error, Refusal.t()}
  def normalize(%Elixir.SPARQL.Query.Result{results: results}) when is_list(results) do
    {:ok, :bindings, Enum.map(results, &normalize_binding/1)}
  end

  def normalize(%Elixir.SPARQL.Query.Result{results: result}) when is_boolean(result) do
    {:ok, :boolean, [%{"ask" => result}]}
  end

  def normalize(data) do
    try do
      rows = data |> RDF.Data.statements() |> Enum.map(&normalize_statement/1)
      {:ok, :rdf, rows}
    rescue
      _ ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :sparql_result,
           "unsupported SPARQL result shape",
           %{result: inspect(data)}
         )}
    end
  end

  @spec hash_rows(list()) :: String.t()
  def hash_rows(rows) do
    rows
    |> AshR2RML.Parity.normalize_multiset()
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_binding(binding) when is_map(binding) do
    Map.new(binding, fn {key, value} -> {normalize_var_name(key), normalize_term(value)} end)
  end

  defp normalize_var_name(%{name: name}), do: to_string(name)
  defp normalize_var_name(key) when is_atom(key), do: Atom.to_string(key) |> String.trim_leading("?")
  defp normalize_var_name(key) when is_binary(key), do: String.trim_leading(key, "?")
  defp normalize_var_name(other), do: other |> to_string() |> String.trim_leading("?")

  defp normalize_statement({subject, predicate, object}) do
    %{
      "subject" => normalize_term(subject),
      "predicate" => normalize_term(predicate),
      "object" => normalize_term(object)
    }
  end

  defp normalize_statement({subject, predicate, object, graph_name}) do
    %{
      "subject" => normalize_term(subject),
      "predicate" => normalize_term(predicate),
      "object" => normalize_term(object),
      "graph" => normalize_term(graph_name)
    }
  end

  defp normalize_term(nil), do: nil

  defp normalize_term(value) do
    if RDF.Term.term?(value), do: RDF.Term.value(value), else: value
  rescue
    _ -> value
  end
end

defmodule AshR2RML.SPARQL.Local do
  @moduledoc "Explicit SPARQL.ex execution against an RDF.ex data structure."

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @spec query(RDF.Data.Source.t(), String.t() | Query.t()) ::
          {:ok, Observation.t()} | {:error, Refusal.t()}
  def query(data, query) do
    with {:ok, admitted} <- Query.admit(query) do
      try do
        result = Elixir.SPARQL.execute_query(data, admitted.parsed)

        with {:ok, result_kind, rows} <- normalize_local_result(admitted.form, result) do
          {:ok,
           %Observation{
             strategy: :local_rdf,
             query_sha256: admitted.sha256,
             query_form: admitted.form,
             status: :PARTIAL_ALIVE,
             standing: :observed_local_rdf_execution,
             evidence_kind: :in_memory_execution,
             result_kind: result_kind,
             result_sha256: Result.hash_rows(rows),
             rows: rows,
             metadata: %{engine: :sparql_ex}
           }}
        end
      rescue
        exception ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :local_sparql_execution,
             "SPARQL.ex could not execute the admitted query against the supplied RDF data",
             %{
               query_form: admitted.form,
               exception: Exception.message(exception),
               engine_scope: :sparql_ex_local
             }
           )}
      end
    end
  end

  # SPARQL.ex 0.3.x represents local ASK truth as a solution sequence:
  # one empty binding for true and an empty sequence for false. Normalize that
  # engine-specific representation into the same boolean observation contract
  # used by protocol ASK results before knowledge-hook evaluation sees it.
  defp normalize_local_result(:ask, result) do
    case Result.normalize(result) do
      {:ok, :boolean, _rows} = normalized -> normalized
      {:ok, :bindings, rows} -> {:ok, :boolean, [%{"ask" => rows != []}]}
      other -> other
    end
  end

  defp normalize_local_result(_form, result), do: Result.normalize(result)
end

defmodule AshR2RML.SPARQL.Protocol do
  @moduledoc """
  Read-only W3C SPARQL Protocol execution through SPARQL.Client.

  SPARQL.Client also implements update operations, but this module deliberately
  exposes queries only. Verification capability never manufactures remote
  mutation authority.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Observation, Query, Result}

  @spec query(String.t(), String.t() | Query.t(), keyword()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query(endpoint, query, opts \\ []) when is_binary(endpoint) do
    do_query(
      endpoint,
      query,
      opts,
      &Elixir.SPARQL.Client.query/3,
      :sparql_protocol,
      :observed_remote_query
    )
  end

  @doc "Injected client path for deterministic unit tests. Never a remote-query witness."
  @spec query_with(String.t(), String.t() | Query.t(), keyword(), function()) ::
          {:ok, Observation.t()} | {:error, term()}
  def query_with(endpoint, query, opts, client_fun)
      when is_binary(endpoint) and is_function(client_fun, 3) do
    do_query(endpoint, query, opts, client_fun, :injected_client, :test_double_only)
  end

  defp do_query(endpoint, query, opts, client_fun, evidence_kind, standing) do
    with {:ok, admitted} <- Query.admit(query),
         {:ok, result} <- client_fun.(admitted.parsed, endpoint, opts),
         {:ok, result_kind, rows} <- Result.normalize(result) do
      {:ok,
       %Observation{
         strategy: :protocol,
         query_sha256: admitted.sha256,
         query_form: admitted.form,
         status: :PARTIAL_ALIVE,
         standing: standing,
         evidence_kind: evidence_kind,
         endpoint: endpoint,
         result_kind: result_kind,
         result_sha256: Result.hash_rows(rows),
         rows: rows,
         metadata: %{client: :sparql_client}
       }}
    else
      {:error, %Refusal{} = refusal} ->
        {:error, refusal}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           endpoint,
           "SPARQL protocol client returned an unrecognized result",
           %{result: inspect(other)}
         )}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         endpoint,
         "SPARQL protocol query raised",
         %{exception: Exception.message(exception)}
       )}
  end
end

defmodule AshR2RML.SPARQL.Plan do
  @moduledoc "DfCM execution plan preserving all currently lawful SPARQL execution candidates."

  @enforce_keys [:query, :candidates]
  defstruct [:query, :selected, candidates: [], context: %{}]

  @type strategy :: :local_rdf | :protocol | :ontop_cli
  @type t :: %__MODULE__{
          query: AshR2RML.SPARQL.Query.t(),
          selected: strategy() | nil,
          candidates: [strategy()],
          context: map()
        }
end

defmodule AshR2RML.SPARQL do
  @moduledoc """
  DfCM SPARQL execution calculus.

  Local RDF execution, SPARQL Protocol execution, and the existing Ontop CLI
  path remain distinct candidates. Multiple available candidates remain
  unresolved until the caller explicitly closes the choice.
  """

  alias AshR2RML.Refusal
  alias AshR2RML.SPARQL.{Local, Observation, Plan, Protocol, Query, Result}

  @spec explore(String.t() | Query.t(), keyword()) :: {:ok, Plan.t()} | {:error, Refusal.t()}
  def explore(query, opts \\ []) do
    with {:ok, admitted} <- Query.admit(query) do
      candidates =
        []
        |> maybe_candidate(not is_nil(Keyword.get(opts, :data)), :local_rdf)
        |> maybe_candidate(is_binary(Keyword.get(opts, :endpoint)), :protocol)
        |> maybe_candidate(not is_nil(Keyword.get(opts, :ontop)), :ontop_cli)

      build_plan(admitted, candidates, opts)
    end
  end

  @spec execute(Plan.t()) :: {:ok, Observation.t()} | {:error, term()}
  def execute(%Plan{selected: nil} = plan) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_execution,
       "multiple lawful SPARQL execution candidates remain; explicit selection is required",
       %{candidates: plan.candidates}
     )}
  end

  def execute(%Plan{selected: :local_rdf, query: query, context: %{data: data}})
      when not is_nil(data),
      do: Local.query(data, query)

  def execute(%Plan{selected: :protocol, query: query, context: %{endpoint: endpoint} = context})
      when is_binary(endpoint),
      do: Protocol.query(endpoint, query, context.client_opts)

  def execute(%Plan{selected: :ontop_cli, query: query, context: %{ontop: ontop}})
      when is_map(ontop) do
    with {:ok, observation} <- AshR2RML.OBDA.Ontop.query(Map.put_new(ontop, :query, query.source)) do
      rows = observation.rows

      {:ok,
       %Observation{
         strategy: :ontop_cli,
         query_sha256: query.sha256,
         query_form: query.form,
         status: observation.status,
         standing: observation.standing,
         evidence_kind: observation.evidence_kind,
         result_kind: :bindings,
         result_sha256: Result.hash_rows(rows),
         rows: rows,
         metadata: %{engine: :ontop, mapping_sha256: observation.mapping_sha256}
       }}
    end
  end

  def execute(%Plan{} = plan) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_execution,
       "selected SPARQL execution strategy lacks its required execution context",
       %{selected: plan.selected, candidates: plan.candidates}
     )}
  end

  defp build_plan(_query, [], _opts) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :sparql_execution,
       "no SPARQL execution candidate was supplied",
       %{expected: [:data, :endpoint, :ontop]}
     )}
  end

  defp build_plan(query, candidates, opts) do
    explicit = Keyword.get(opts, :strategy)

    if explicit && explicit not in candidates do
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :sparql_execution,
         "selected SPARQL execution strategy is not available",
         %{selected: explicit, candidates: candidates}
       )}
    else
      selected = explicit || if(length(candidates) == 1, do: hd(candidates))

      {:ok,
       %Plan{
         query: query,
         candidates: candidates,
         selected: selected,
         context: %{
           data: Keyword.get(opts, :data),
           endpoint: Keyword.get(opts, :endpoint),
           client_opts: Keyword.get(opts, :client_opts, []),
           ontop: Keyword.get(opts, :ontop)
         }
       }}
    end
  end

  defp maybe_candidate(values, true, candidate), do: values ++ [candidate]
  defp maybe_candidate(values, false, _candidate), do: values
end

defmodule AshR2RML.JSONLD do
  @moduledoc """
  JSON-LD 1.1 projection and ingestion through JSON-LD.ex.

  JSON-LD and Turtle are alternate RDF serializations feeding the same SHACL
  admission boundary. Remote contexts are refused by default because ambient
  network context resolution would make compilation depend on mutable external
  state without a receipt.
  """

  alias AshR2RML.Refusal

  @spec to_rdf(String.t() | map() | list(), keyword()) ::
          {:ok, RDF.Dataset.t()} | {:error, Refusal.t()}
  def to_rdf(input, opts \\ []) do
    try do
      with {:ok, document} <- decode_document(input),
           :ok <- admit_contexts(document, opts) do
        {:ok, JSON.LD.to_rdf(document)}
      end
    rescue
      exception -> jsonld_error(:to_rdf, exception)
    end
  end

  @spec ingest(String.t() | map() | list(), keyword()) :: {:ok, map()} | {:error, term()}
  def ingest(input, opts \\ []) do
    source = if is_binary(input), do: input, else: Jason.encode!(input)

    with {:ok, data} <- to_rdf(input, opts) do
      AshR2RML.Ingestion.from_graph(data, Keyword.put_new(opts, :source_sha256, sha256(source)))
    end
  end

  @spec compile(String.t() | map() | list(), keyword()) ::
          {:ok, AshR2RML.Mapping.Bundle.t()} | {:error, term()}
  def compile(input, opts \\ []) do
    with {:ok, profile} <- ingest(input, opts),
         {:ok, compilation} <- AshR2RML.Compiler.compile(profile) do
      {:ok, compilation.mapping_bundle}
    end
  end

  @spec expand(String.t() | map() | list(), keyword()) :: {:ok, term()} | {:error, Refusal.t()}
  def expand(input, opts \\ []) do
    try do
      with {:ok, document} <- decode_document(input),
           :ok <- admit_contexts(document, opts) do
        {:ok, JSON.LD.expand(document)}
      end
    rescue
      exception -> jsonld_error(:expand, exception)
    end
  end

  @spec compact(String.t() | map() | list(), map() | String.t(), keyword()) ::
          {:ok, map()} | {:error, Refusal.t()}
  def compact(input, context, opts \\ []) do
    try do
      with {:ok, document} <- decode_document(input),
           :ok <- admit_contexts(document, opts),
           :ok <- admit_contexts(%{"@context" => context}, opts) do
        {:ok, JSON.LD.compact(document, context)}
      end
    rescue
      exception -> jsonld_error(:compact, exception)
    end
  end

  @spec encode_rdf(RDF.Data.Source.t(), keyword()) :: {:ok, String.t()} | {:error, Refusal.t()}
  def encode_rdf(data, opts \\ []) do
    try do
      doc =
        case JSON.LD.from_rdf(data) do
          {:ok, d} -> d
          d -> d
        end

      with {:ok, document} <- maybe_compact(doc, opts),
           {:ok, json} <- Jason.encode(document, json_options(opts)) do
        {:ok, json}
      else
        {:error, %Refusal{} = refusal} -> {:error, refusal}
        {:error, reason} -> jsonld_error(:encode, reason)
      end
    rescue
      exception -> jsonld_error(:encode, exception)
    end
  end

  defp maybe_compact(document, opts) do
    case Keyword.get(opts, :context) do
      nil ->
        {:ok, document}

      context ->
        with :ok <- admit_contexts(%{"@context" => context}, opts) do
          {:ok, JSON.LD.compact(document, context)}
        end
    end
  end

  defp json_options(opts), do: if(Keyword.get(opts, :pretty, true), do: [pretty: true], else: [])

  defp decode_document(input) when is_map(input) or is_list(input), do: {:ok, input}

  defp decode_document(input) when is_binary(input) do
    case Jason.decode(input) do
      {:ok, document} ->
        {:ok, document}

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :jsonld,
           "invalid JSON-LD JSON syntax",
           %{reason: inspect(reason)}
         )}
    end
  end

  defp decode_document(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :jsonld,
       "expected decoded JSON-LD object/list or JSON string",
       %{got: inspect(other)}
     )}
  end

  defp admit_contexts(document, opts) do
    remote = document |> remote_contexts() |> Enum.uniq() |> Enum.sort()

    if remote == [] or Keyword.get(opts, :allow_remote_contexts?, false) do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :jsonld_context,
         "remote JSON-LD context resolution is not admitted by default",
         %{remote_contexts: remote, opt_in: :allow_remote_contexts?}
       )}
    end
  end

  defp remote_contexts(%{} = map) do
    Enum.flat_map(map, fn
      {"@context", value} -> context_urls(value) ++ remote_contexts(value)
      {"@import", value} -> context_urls(value) ++ remote_contexts(value)
      {_key, value} -> remote_contexts(value)
    end)
  end

  defp remote_contexts(list) when is_list(list), do: Enum.flat_map(list, &remote_contexts/1)
  defp remote_contexts(_), do: []

  # Only a string/list occupying @context or @import is a remote context reference.
  # IRI-valued term definitions inside an inline context map are ordinary mappings.
  defp context_urls(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme} when scheme in ["http", "https"] -> [value]
      _ -> []
    end
  end

  defp context_urls(list) when is_list(list), do: Enum.flat_map(list, &context_urls/1)
  defp context_urls(_), do: []

  defp jsonld_error(operation, exception) do
    reason = if is_exception(exception), do: Exception.message(exception), else: inspect(exception)

    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :jsonld,
       "JSON-LD #{operation} failed",
       %{reason: reason}
     )}
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

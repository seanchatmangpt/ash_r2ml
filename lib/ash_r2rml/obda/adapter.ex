# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.OBDA.Adapter do
  @moduledoc """
  Behaviour for OBDA query engines, so a caller can dispatch to whichever
  engine a given mapping/resource actually needs without hand-checking which
  concrete module to call.

  AshR2RML today has two independently-evolved OBDA execution paths --
  `AshR2RML.OBDA.Ontop` (real Ontop CLI process, SPARQL-to-SQL rewriting over a
  JDBC-connected Postgres) and `AshR2RML.OBDA.InMemory` (real `Ash.read!/2` +
  in-process SPARQL algebra, for any data layer Ontop cannot reach) -- with no
  shared interface between them. This behaviour is modeled after Gno's
  `Gno.Store.Adapter` (`~/gno/lib/gno/store/adapter.ex`): a minimal callback
  contract that lets a caller `dispatch/2` by config-struct type, the same way
  `Gno.Store` pattern-matches `%adapter_type{}` to call `adapter_type.<fn>`.

  What is deliberately **not** ported from `Gno.Store.Adapter`: SPARQL Graph
  Store Protocol endpoint resolution (`determine_query_endpoint/1`,
  `determine_update_endpoint/1`, `determine_graph_store_endpoint/1`), HTTP
  dispatch (`Gno.Store.GenSPARQL`), and default/union graph-semantics
  configuration. AshR2RML never talks to a live SPARQL protocol server -- Ontop
  is invoked as a one-shot CLI process per query, and `InMemory` never leaves
  the BEAM -- so there is no persistent store connection to abstract over.
  """

  alias AshR2RML.Refusal

  @doc "The engine's canonical identifier, e.g. `:ontop` or `:in_memory`."
  @callback engine_name() :: atom()

  @doc """
  Executes `sparql` against whatever `config` names (a mapping file pair for
  Ontop, an Ash resource + mapping IR for InMemory), returning an
  engine-specific observation struct wrapped in `{:ok, _}` on success or
  `{:error, %Refusal{}}` / `{:error, observation}` on failure -- unified only
  at the ok/error-tuple level, since the two engines' observation structs
  (`AshR2RML.OBDA.Observation` vs `AshR2RML.SPARQL.Observation`) carry
  genuinely different evidence (an external process's exit status and stdout
  vs. an in-process materialization's row set) and forcing them into one shape
  would erase real information rather than unify a real abstraction.
  """
  @callback query(config :: struct() | keyword() | map(), sparql :: String.t(), opts :: keyword()) ::
              {:ok, struct()} | {:error, struct() | Refusal.t()}

  @doc """
  Dispatches `query/3` to the adapter module matching `config`'s struct type
  (mirroring `Gno.Store`'s `%adapter_type{} -> adapter_type.<fn>` dispatch).
  """
  @spec dispatch(struct(), String.t(), keyword()) :: {:ok, struct()} | {:error, struct() | Refusal.t()}
  def dispatch(%module{} = config, sparql, opts \\ []) when is_binary(sparql) do
    module.query(config, sparql, opts)
  end
end

defmodule AshR2RML.OBDA.Adapter.OntopConfig do
  @moduledoc """
  `AshR2RML.OBDA.Adapter` config for the real Ontop CLI adapter. Wraps the
  keyword/map options `AshR2RML.OBDA.Ontop.query/1` already accepts
  (`:mapping_path`, `:query_path`, `:properties_path`, etc.) in a typed struct
  so `AshR2RML.OBDA.Adapter.dispatch/3` can pattern-match on it.
  """

  @behaviour AshR2RML.OBDA.Adapter

  defstruct [
    :mapping_path,
    :properties_path,
    :ontology_path,
    :db_url,
    :db_user,
    :db_password,
    :db_driver,
    :facts_path,
    :lenses_path,
    :sparql_rules_path,
    :binary,
    prefix_args: []
  ]

  @type t :: %__MODULE__{}

  @impl true
  def engine_name, do: :ontop

  @impl true
  def query(%__MODULE__{} = config, sparql, opts) when is_binary(sparql) do
    query_path = Keyword.get(opts, :query_path)

    ontop_opts =
      config
      |> Map.from_struct()
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Keyword.new()
      |> Keyword.put_new(:query, sparql)
      |> then(fn kw -> if query_path, do: Keyword.put(kw, :query_path, query_path), else: kw end)

    AshR2RML.OBDA.Ontop.query(ontop_opts)
  end
end

defmodule AshR2RML.OBDA.Adapter.InMemoryConfig do
  @moduledoc """
  `AshR2RML.OBDA.Adapter` config for the in-process `AshR2RML.OBDA.InMemory`
  adapter. Wraps one or more `{ash_resource, mapping_resource}` specs so
  `AshR2RML.OBDA.Adapter.dispatch/3` can route to `query/4` (single resource)
  or `query_many/3` (multiple resources with relationships) uniformly.
  """

  @behaviour AshR2RML.OBDA.Adapter

  defstruct [:specs, read_opts: []]

  @type t :: %__MODULE__{
          specs: [AshR2RML.OBDA.InMemory.spec()],
          read_opts: keyword()
        }

  @impl true
  def engine_name, do: :in_memory

  @impl true
  def query(%__MODULE__{specs: [{ash_resource, mapping_resource}]} = config, sparql, opts)
      when is_binary(sparql) do
    read_opts = Keyword.merge(config.read_opts, opts)
    AshR2RML.OBDA.InMemory.query(ash_resource, mapping_resource, sparql, read_opts)
  end

  def query(%__MODULE__{specs: specs} = config, sparql, opts)
      when is_list(specs) and is_binary(sparql) do
    read_opts = Keyword.merge(config.read_opts, opts)
    AshR2RML.OBDA.InMemory.query_many(specs, sparql, read_opts)
  end
end

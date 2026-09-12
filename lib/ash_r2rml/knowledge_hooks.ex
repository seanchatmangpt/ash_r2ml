# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Predicate do
  @moduledoc "Read-only predicate admitted for a knowledge hook."

  @enforce_keys [:type]
  defstruct [:type, :query, :query_sha256, :query_form]

  @type t :: %__MODULE__{
          type: :ask | :result_delta | :external_trigger,
          query: AshR2RML.SPARQL.Query.t() | nil,
          query_sha256: String.t() | nil,
          query_form: atom() | nil
        }
end

defmodule AshR2RML.KnowledgeHook.Definition do
  @moduledoc "Admitted knowledge-hook definition. The intent is data, never executable authority."

  @enforce_keys [:id, :name, :trigger_type, :predicate, :intent]
  defstruct [
    :id,
    :name,
    :trigger_type,
    :trigger_pattern,
    :predicate,
    :intent,
    require_actuation_receipt?: true,
    provenance: %{}
  ]

  @type trigger_type :: :rdf_change | :sparql_result | :interval | :event
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          trigger_type: trigger_type(),
          trigger_pattern: term(),
          predicate: AshR2RML.KnowledgeHook.Predicate.t(),
          intent: map(),
          require_actuation_receipt?: true,
          provenance: map()
        }
end

defmodule AshR2RML.KnowledgeHook.Plan do
  @moduledoc "Content-addressed knowledge-hook plan with construct-only standing."

  @enforce_keys [:hooks, :plan_sha256]
  defstruct hooks: [],
            source_identity: %{},
            plan_sha256: nil,
            status: :PARTIAL_ALIVE,
            standing: :admitted_construct_only,
            authority: :UNAUTHORIZED

  @type t :: %__MODULE__{
          hooks: [AshR2RML.KnowledgeHook.Definition.t()],
          source_identity: map(),
          plan_sha256: String.t(),
          status: :PARTIAL_ALIVE,
          standing: :admitted_construct_only,
          authority: :UNAUTHORIZED
        }
end

defmodule AshR2RML.KnowledgeHook.Intent do
  @moduledoc "Constructed downstream intent. This value deliberately has no runner or DO authority."

  @enforce_keys [:hook_id, :kind, :target, :evaluation_receipt_sha256]
  defstruct [
    :hook_id,
    :kind,
    :target,
    :payload,
    :evaluation_receipt_sha256,
    :trigger_type,
    authority: :UNAUTHORIZED,
    standing: :constructed_not_actuated,
    requires_actuation_receipt?: true
  ]
end

defmodule AshR2RML.KnowledgeHook.EvaluationReceipt do
  @moduledoc "Receipt for observed predicate evaluation and optional intent construction."

  @enforce_keys [:receipt_sha256, :hook_id, :plan_sha256, :matched?, :identity]
  defstruct [
    :receipt_sha256,
    :hook_id,
    :plan_sha256,
    :predicate_type,
    :predicate_sha256,
    :current_result_sha256,
    :previous_result_sha256,
    :external_trigger_receipt_sha256,
    :matched?,
    :identity,
    :replay,
    status: :PARTIAL_ALIVE,
    standing: :observed_predicate_only,
    authority: :UNAUTHORIZED,
    consequence: :none,
    executed: [],
    verified: [],
    blocked: [:actuation_authority]
  ]
end

defmodule AshR2RML.KnowledgeHook.Evaluation do
  @moduledoc "One hook evaluation. A matched hook manufactures an intent but performs no action."

  @enforce_keys [:hook_id, :matched?, :receipt]
  defstruct [:hook_id, :matched?, :intent, :receipt, observations: []]

  @type t :: %__MODULE__{
          hook_id: String.t(),
          matched?: boolean(),
          intent: map() | nil,
          receipt: map(),
          observations: [AshR2RML.SPARQL.Observation.t()]
        }
end

defmodule AshR2RML.KnowledgeHooks do
  @moduledoc """
  Evidence-bounded knowledge-hook support for AshR2RML.

  Knowledge hooks are admitted semantic predicates which may manufacture a
  downstream intent. They do not execute that intent. Query evaluation reuses
  `AshR2RML.SPARQL`, while event/time/RDF-change triggers require an externally
  observed trigger receipt.

  The first-class interoperability adapters recognize the established GitVan
  Graph Hook vocabulary and the KNHK ontology. GitVan pipeline nodes and KNHK
  actions are retained as opaque intent targets; neither vocabulary grants DO
  authority inside AshR2RML.
  """

  alias AshR2RML.KnowledgeHook.{Definition, Evaluation, EvaluationReceipt, Intent, Plan, Predicate}
  alias AshR2RML.{Compiler, Refusal}

  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @rdfs_label "http://www.w3.org/2000/01/rdf-schema#label"
  @dct_title "http://purl.org/dc/terms/title"
  @gitvan_gh "https://gitvan.dev/graph-hook#"
  @gitvan_gv "https://gitvan.dev/ontology#"
  @knhk "http://knhk.io/ontology#"

  @ambient_keys [
    :handler,
    "handler",
    :callback,
    "callback",
    :executor,
    "executor",
    :execute_fun,
    "execute_fun",
    :run_fun,
    "run_fun"
  ]

  @doc "Admit normalized hook definitions into a deterministic construct-only plan."
  @spec admit([map()], keyword()) :: {:ok, Plan.t()} | {:error, [Refusal.t()]}
  def admit(definitions, opts \\ [])

  def admit(definitions, opts) when is_list(definitions) and is_list(opts) do
    with {:ok, hooks} <- normalize_definitions(definitions),
         :ok <- unique_ids(hooks) do
      hooks = Enum.sort_by(hooks, & &1.id)
      source_identity = Keyword.get(opts, :source_identity, %{})

      plan_sha256 =
        Compiler.sha256(%{
          version: 1,
          source_identity: canonical(source_identity),
          hooks: Enum.map(hooks, &canonical_definition/1)
        })

      {:ok,
       %Plan{
         hooks: hooks,
         source_identity: source_identity,
         plan_sha256: plan_sha256
       }}
    else
      {:error, %Refusal{} = refusal} -> {:error, [refusal]}
      {:error, refusals} when is_list(refusals) -> {:error, refusals}
    end
  end

  def admit(other, _opts) do
    {:error,
     [
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hooks,
         "knowledge-hook definitions must be a list",
         %{got: inspect(other)}
       )
     ]}
  end

  @doc "Parse GitVan/KNHK knowledge hooks from Turtle and admit a deterministic plan."
  @spec from_turtle(String.t(), keyword()) :: {:ok, Plan.t()} | {:error, [Refusal.t()]}
  def from_turtle(turtle, opts \\ []) when is_binary(turtle) and is_list(opts) do
    case RDF.Turtle.read_string(turtle) do
      {:ok, graph} ->
        source_identity =
          Keyword.get(opts, :source_identity, %{})
          |> Map.put_new(:hook_graph_sha256, Compiler.sha256(turtle))

        from_graph(graph, Keyword.put(opts, :source_identity, source_identity))

      {:error, reason} ->
        {:error,
         [
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :knowledge_hook_turtle,
             "failed to parse knowledge-hook Turtle",
             %{reason: inspect(reason)}
           )
         ]}
    end
  rescue
    exception ->
      {:error,
       [
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_turtle,
           "knowledge-hook Turtle parsing raised",
           %{reason: Exception.message(exception)}
         )
       ]}
  end

  @doc "Extract supported GitVan/KNHK hook definitions from an RDF graph."
  @spec from_graph(RDF.Data.Source.t(), keyword()) :: {:ok, Plan.t()} | {:error, [Refusal.t()]}
  def from_graph(graph, opts \\ []) when is_list(opts) do
    statements = RDF.Data.statements(graph)
    index = index_statements(statements)

    gitvan_hooks = subjects_of_type(statements, @gitvan_gh <> "Hook")
    knhk_hooks = subjects_of_type(statements, @knhk <> "Hook")

    if gitvan_hooks == [] and knhk_hooks == [] do
      {:error,
       [
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hooks,
           "RDF graph contains no supported knowledge-hook subjects",
           %{supported_types: [@gitvan_gh <> "Hook", @knhk <> "Hook"]}
         )
       ]}
    else
      with {:ok, gitvan_definitions} <- parse_many(gitvan_hooks, &parse_gitvan_hook(&1, index)),
           {:ok, knhk_definitions} <- parse_many(knhk_hooks, &parse_knhk_hook(&1, index)) do
        source_identity =
          Keyword.get(opts, :source_identity, %{})
          |> Map.put_new(:hook_graph_sha256, graph_sha256(statements))

        admit(gitvan_definitions ++ knhk_definitions, source_identity: source_identity)
      end
    end
  rescue
    exception ->
      {:error,
       [
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_graph,
           "failed to inspect knowledge-hook RDF graph",
           %{reason: Exception.message(exception)}
         )
       ]}
  end

  @doc "Evaluate every hook predicate and construct intents for matches without actuating them."
  @spec evaluate(Plan.t(), keyword()) :: {:ok, [Evaluation.t()]} | {:error, Refusal.t()}
  def evaluate(%Plan{} = plan, opts \\ []) when is_list(opts) do
    Enum.reduce_while(plan.hooks, {:ok, []}, fn hook, {:ok, acc} ->
      case evaluate_hook(hook, plan.plan_sha256, opts) do
        {:ok, evaluation} -> {:cont, {:ok, [evaluation | acc]}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, evaluations} -> {:ok, Enum.reverse(evaluations)}
      error -> error
    end
  end

  @doc "Pure deterministic projection suitable for ggen path/content manufacture."
  @spec projection(Plan.t()) :: map()
  def projection(%Plan{} = plan) do
    %{
      version: 1,
      status: plan.status,
      standing: plan.standing,
      authority: plan.authority,
      plan_sha256: plan.plan_sha256,
      source_identity: plan.source_identity,
      hooks: Enum.map(plan.hooks, &projection_definition/1)
    }
  end

  defp normalize_definitions(definitions) do
    Enum.reduce_while(definitions, {:ok, []}, fn raw, {:ok, acc} ->
      case normalize_definition(raw) do
        {:ok, definition} -> {:cont, {:ok, [definition | acc]}}
        {:error, refusal} -> {:halt, {:error, refusal}}
      end
    end)
    |> case do
      {:ok, hooks} -> {:ok, Enum.reverse(hooks)}
      error -> error
    end
  end

  defp normalize_definition(raw) when is_map(raw) do
    id = get(raw, :id)
    name = get(raw, :name, id)
    trigger_type = normalize_trigger_type(get(raw, :trigger_type, :sparql_result))
    intent_raw = get(raw, :intent, get(raw, :action, get(raw, :pipeline)))
    receipt_required? = get(raw, :require_actuation_receipt?, true)

    cond do
      ambient_actuation?(raw) ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id || :knowledge_hook,
           "knowledge-hook definition contains ambient executable authority",
           %{forbidden_keys: present_ambient_keys(raw)}
         )}

      not is_binary(id) or id == "" ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook,
           "knowledge hook requires a stable non-empty string id"
         )}

      not is_binary(name) or name == "" ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id,
           "knowledge hook requires a non-empty name"
         )}

      trigger_type == :unsupported ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id,
           "unsupported knowledge-hook trigger type",
           %{trigger_type: get(raw, :trigger_type)}
         )}

      receipt_required? != true ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id,
           "knowledge-hook intent must require a downstream actuation receipt"
         )}

      true ->
        with {:ok, predicate} <- normalize_predicate(get(raw, :predicate), trigger_type, id),
             {:ok, intent} <- normalize_intent(intent_raw, id) do
          {:ok,
           %Definition{
             id: id,
             name: name,
             trigger_type: trigger_type,
             trigger_pattern: get(raw, :trigger_pattern),
             predicate: predicate,
             intent: intent,
             require_actuation_receipt?: true,
             provenance: get(raw, :provenance, %{})
           }}
        end
    end
  end

  defp normalize_definition(other) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       :knowledge_hook,
       "knowledge-hook definition must be a map",
       %{got: inspect(other)}
     )}
  end

  defp normalize_predicate(nil, trigger_type, _id)
       when trigger_type in [:rdf_change, :interval, :event],
       do: {:ok, %Predicate{type: :external_trigger}}

  defp normalize_predicate(nil, _trigger_type, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "SPARQL-result hook requires an admitted predicate"
     )}
  end

  defp normalize_predicate(raw, _trigger_type, id) when is_map(raw) do
    type = normalize_predicate_type(get(raw, :type))
    query = get(raw, :query)

    case type do
      :external_trigger ->
        {:ok, %Predicate{type: :external_trigger}}

      type when type in [:ask, :result_delta] ->
        with {:ok, admitted} <- AshR2RML.SPARQL.Query.admit(query),
             :ok <- verify_query_form(type, admitted, id) do
          {:ok,
           %Predicate{
             type: type,
             query: admitted,
             query_sha256: admitted.sha256,
             query_form: admitted.form
           }}
        end

      _ ->
        {:error,
         Refusal.new(
           :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
           id,
           "unsupported knowledge-hook predicate type",
           %{predicate_type: get(raw, :type), supported: [:ask, :result_delta, :external_trigger]}
         )}
    end
  end

  defp normalize_predicate(other, _trigger_type, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "knowledge-hook predicate must be a map",
       %{got: inspect(other)}
     )}
  end

  defp verify_query_form(:ask, %{form: :ask}, _id), do: :ok

  defp verify_query_form(:result_delta, %{form: form}, _id)
       when form in [:select, :ask, :construct, :describe],
       do: :ok

  defp verify_query_form(type, admitted, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
       id,
       "predicate/query form mismatch",
       %{predicate_type: type, query_form: admitted.form}
     )}
  end

  defp normalize_intent(nil, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "knowledge hook requires an opaque downstream intent target"
     )}
  end

  defp normalize_intent(raw, _id) when is_binary(raw) or is_atom(raw) do
    {:ok, %{kind: :opaque_target, target: raw, payload: %{}}}
  end

  defp normalize_intent(raw, id) when is_map(raw) do
    target = get(raw, :target, get(raw, :action, get(raw, :pipeline)))
    kind = get(raw, :kind, :opaque_target)
    payload = get(raw, :payload, %{})

    if is_nil(target) or not inert_term?(raw) do
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         id,
         "knowledge-hook intent must be inert data with a target",
         %{intent: inspect(raw)}
       )}
    else
      {:ok, %{kind: kind, target: target, payload: payload}}
    end
  end

  defp normalize_intent(other, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "knowledge-hook intent must be inert data",
       %{intent: inspect(other)}
     )}
  end

  defp unique_ids(hooks) do
    duplicates =
      hooks
      |> Enum.group_by(& &1.id)
      |> Enum.filter(fn {_id, values} -> length(values) > 1 end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    if duplicates == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         :knowledge_hooks,
         "knowledge-hook ids must be unique",
         %{duplicates: duplicates}
       )}
    end
  end

  defp evaluate_hook(%Definition{predicate: %Predicate{type: :ask} = predicate} = hook, plan_sha256, opts) do
    with {:ok, observation} <- execute_query(predicate.query, current_opts(opts)),
         {:ok, matched?} <- boolean_result(observation, hook.id) do
      build_evaluation(hook, plan_sha256, matched?, [observation], nil)
    end
  end

  defp evaluate_hook(
         %Definition{predicate: %Predicate{type: :result_delta} = predicate} = hook,
         plan_sha256,
         opts
       ) do
    previous = previous_opts(opts)

    if previous == [] do
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         hook.id,
         "result-delta hook requires an explicit previous observation context"
       )}
    else
      with {:ok, previous_observation} <- execute_query(predicate.query, previous),
           {:ok, current_observation} <- execute_query(predicate.query, current_opts(opts)) do
        matched? = current_observation.result_sha256 != previous_observation.result_sha256
        build_evaluation(hook, plan_sha256, matched?, [previous_observation, current_observation], nil)
      end
    end
  end

  defp evaluate_hook(
         %Definition{predicate: %Predicate{type: :external_trigger}} = hook,
         plan_sha256,
         opts
       ) do
    with {:ok, witness} <- external_trigger_witness(hook.id, opts) do
      matched? = get(witness, :matched?, true) == true
      build_evaluation(hook, plan_sha256, matched?, [], get(witness, :receipt_sha256))
    end
  end

  defp execute_query(query, opts) do
    with {:ok, plan} <- AshR2RML.SPARQL.explore(query, opts),
         {:ok, observation} <- AshR2RML.SPARQL.execute(plan) do
      {:ok, observation}
    end
  end

  defp boolean_result(%{result_kind: :boolean, rows: [%{"ask" => value}]}, _id)
       when is_boolean(value),
       do: {:ok, value}

  defp boolean_result(observation, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "ASK knowledge-hook predicate did not produce one boolean result",
       %{result_kind: observation.result_kind, rows: observation.rows}
     )}
  end

  defp build_evaluation(hook, plan_sha256, matched?, observations, external_receipt) do
    observation_hashes = Enum.map(observations, & &1.result_sha256)
    predicate_sha256 = hook.predicate.query_sha256

    core = %{
      hook_id: hook.id,
      plan_sha256: plan_sha256,
      predicate_type: hook.predicate.type,
      predicate_sha256: predicate_sha256,
      current_result_sha256: List.last(observation_hashes),
      previous_result_sha256: if(length(observation_hashes) > 1, do: hd(observation_hashes), else: nil),
      external_trigger_receipt_sha256: external_receipt,
      matched?: matched?,
      authority: :UNAUTHORIZED,
      consequence: if(matched?, do: :intent_constructed, else: :none),
      observation_standing: Enum.map(observations, & &1.standing)
    }

    receipt_sha256 = Compiler.sha256(core)
    standing = if matched?, do: :constructed_intent_not_actuated, else: :observed_predicate_only

    receipt =
      %EvaluationReceipt{
        receipt_sha256: receipt_sha256,
        hook_id: hook.id,
        plan_sha256: plan_sha256,
        predicate_type: hook.predicate.type,
        predicate_sha256: predicate_sha256,
        current_result_sha256: core.current_result_sha256,
        previous_result_sha256: core.previous_result_sha256,
        external_trigger_receipt_sha256: external_receipt,
        matched?: matched?,
        identity: %{
          hook_id: hook.id,
          plan_sha256: plan_sha256,
          predicate_sha256: predicate_sha256
        },
        replay: %{
          predicate_type: hook.predicate.type,
          query: hook.predicate.query && hook.predicate.query.source,
          query_form: hook.predicate.query_form,
          observation_strategies: Enum.map(observations, & &1.strategy),
          observation_standing: core.observation_standing,
          current_result_sha256: core.current_result_sha256,
          previous_result_sha256: core.previous_result_sha256,
          external_trigger_receipt_sha256: external_receipt
        },
        standing: standing,
        consequence: core.consequence,
        executed: evaluation_steps(hook.predicate.type, observations),
        verified: [:predicate_identity, :evaluation_receipt_identity],
        blocked: [:actuation_authority]
      }

    intent = if matched?, do: construct_intent(hook, receipt_sha256), else: nil

    {:ok,
     %Evaluation{
       hook_id: hook.id,
       matched?: matched?,
       intent: intent,
       receipt: receipt,
       observations: observations
     }}
  end

  defp construct_intent(hook, receipt_sha256) do
    %Intent{
      hook_id: hook.id,
      kind: hook.intent.kind,
      target: hook.intent.target,
      payload: hook.intent.payload,
      evaluation_receipt_sha256: receipt_sha256,
      trigger_type: hook.trigger_type,
      authority: :UNAUTHORIZED,
      standing: :constructed_not_actuated,
      requires_actuation_receipt?: true
    }
  end

  defp evaluation_steps(:external_trigger, _), do: [:external_trigger_witness_admission, :intent_selection]

  defp evaluation_steps(:result_delta, _),
    do: [:previous_sparql_observation, :current_sparql_observation, :result_delta]

  defp evaluation_steps(:ask, _), do: [:sparql_observation, :ask_evaluation]

  defp external_trigger_witness(hook_id, opts) do
    witnesses = Keyword.get(opts, :trigger_receipts, %{})
    witness = Map.get(witnesses, hook_id) || Keyword.get(opts, :trigger_receipt)

    observed? = is_map(witness) && get(witness, :observed?, false) == true
    receipt_sha256 = is_map(witness) && get(witness, :receipt_sha256)

    if observed? and is_binary(receipt_sha256) and receipt_sha256 != "" do
      {:ok, witness}
    else
      {:error,
       Refusal.new(
         :REFUSED_UNPROVEN_EQUIVALENCE,
         hook_id,
         "external knowledge-hook trigger requires an observed trigger receipt",
         %{required: %{observed?: true, receipt_sha256: "<stable identity>"}}
       )}
    end
  end

  defp current_opts(opts) do
    case Keyword.fetch(opts, :current) do
      {:ok, current} -> current
      :error -> Keyword.take(opts, [:data, :endpoint, :ontop, :strategy, :client_opts])
    end
  end

  defp previous_opts(opts), do: Keyword.get(opts, :previous, [])

  defp parse_gitvan_hook(subject, index) do
    id = term_string(subject)

    with {:ok, predicate_node} <- required_object(index, subject, @gitvan_gh <> "hasPredicate", id),
         {:ok, predicate_type} <- supported_gitvan_predicate(index, predicate_node, id),
         {:ok, query} <- required_literal(index, predicate_node, @gitvan_gh <> "queryText", id),
         {:ok, pipeline} <- required_object(index, subject, @gitvan_gh <> "orderedPipelines", id) do
      name =
        optional_literal(index, subject, @gitvan_gv <> "title") ||
          optional_literal(index, subject, @rdfs_label) ||
          optional_literal(index, subject, @dct_title) || id

      {:ok,
       %{
         id: id,
         name: name,
         trigger_type: :sparql_result,
         trigger_pattern: term_string(predicate_node),
         predicate: %{type: predicate_type, query: query},
         intent: %{kind: :pipeline, target: term_string(pipeline), payload: %{}},
         require_actuation_receipt?: true,
         provenance: %{source: :gitvan_graph_hook, vocabulary: @gitvan_gh}
       }}
    end
  end

  defp supported_gitvan_predicate(index, predicate_node, id) do
    types = objects(index, predicate_node, @rdf_type) |> Enum.map(&term_string/1)

    cond do
      @gitvan_gh <> "ASKPredicate" in types -> {:ok, :ask}
      @gitvan_gh <> "ResultDelta" in types -> {:ok, :result_delta}
      true ->
        {:error,
         Refusal.new(
           :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
           id,
           "GitVan hook predicate type is not supported by the AshR2RML knowledge-hook boundary",
           %{
             predicate_types: types,
             supported: [@gitvan_gh <> "ASKPredicate", @gitvan_gh <> "ResultDelta"]
           }
         )}
    end
  end

  defp parse_knhk_hook(subject, index) do
    id = term_string(subject)

    with {:ok, name} <- required_literal(index, subject, @knhk <> "name", id),
         {:ok, trigger_type_raw} <- required_literal(index, subject, @knhk <> "triggerType", id),
         {:ok, trigger_pattern} <- required_literal(index, subject, @knhk <> "triggerPattern", id),
         {:ok, action} <- required_literal(index, subject, @knhk <> "action", id),
         :ok <- require_knhk_receipt(index, subject, id) do
      trigger_type = normalize_trigger_type(trigger_type_raw)
      check_condition = optional_literal(index, subject, @knhk <> "checkCondition")

      predicate =
        cond do
          is_binary(check_condition) -> %{type: :ask, query: check_condition}
          trigger_type == :sparql_result -> %{type: :result_delta, query: trigger_pattern}
          true -> %{type: :external_trigger}
        end

      {:ok,
       %{
         id: id,
         name: name,
         trigger_type: trigger_type,
         trigger_pattern: trigger_pattern,
         predicate: predicate,
         intent: %{kind: :workflow, target: action, payload: %{}},
         require_actuation_receipt?: true,
         provenance: %{source: :knhk_ontology, vocabulary: @knhk}
       }}
    end
  end

  defp require_knhk_receipt(index, subject, id) do
    case optional_value(index, subject, @knhk <> "emitReceipt") do
      nil -> :ok
      true -> :ok
      "true" -> :ok
      other ->
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id,
           "KNHK hook disables receipts and cannot be admitted for AshR2RML intent manufacture",
           %{emit_receipt: other}
         )}
    end
  end

  defp parse_many(subjects, fun) do
    Enum.reduce_while(subjects, {:ok, []}, fn subject, {:ok, acc} ->
      case fun.(subject) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, refusal} -> {:halt, {:error, [refusal]}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp index_statements(statements) do
    Enum.reduce(statements, %{}, fn statement, acc ->
      {subject, predicate, object} = statement3(statement)
      key = {subject, term_string(predicate)}
      Map.update(acc, key, [object], &[object | &1])
    end)
  end

  defp subjects_of_type(statements, type_iri) do
    statements
    |> Enum.flat_map(fn statement ->
      {subject, predicate, object} = statement3(statement)

      if term_string(predicate) == @rdf_type and term_string(object) == type_iri,
        do: [subject],
        else: []
    end)
    |> Enum.uniq()
    |> Enum.sort_by(&term_string/1)
  end

  defp statement3({subject, predicate, object}), do: {subject, predicate, object}
  defp statement3({subject, predicate, object, _graph_name}), do: {subject, predicate, object}

  defp required_object(index, subject, predicate, id) do
    case objects(index, subject, predicate) do
      [value] -> {:ok, value}
      [] -> {:error, missing_property(id, predicate)}
      values -> {:error, ambiguous_property(id, predicate, values)}
    end
  end

  defp required_literal(index, subject, predicate, id) do
    with {:ok, value} <- required_object(index, subject, predicate, id) do
      normalized = term_value(value)

      if is_binary(normalized) or is_number(normalized) or is_boolean(normalized) do
        {:ok, to_string(normalized)}
      else
        {:error,
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           id,
           "knowledge-hook property must be a scalar literal",
           %{predicate: predicate, value: inspect(value)}
         )}
      end
    end
  end

  defp optional_literal(index, subject, predicate) do
    case objects(index, subject, predicate) do
      [value | _] -> value |> term_value() |> to_string()
      [] -> nil
    end
  end

  defp optional_value(index, subject, predicate) do
    case objects(index, subject, predicate) do
      [value | _] -> term_value(value)
      [] -> nil
    end
  end

  defp objects(index, subject, predicate) do
    index
    |> Map.get({subject, predicate}, [])
    |> Enum.sort_by(&term_string/1)
  end

  defp missing_property(id, predicate) do
    Refusal.new(
      :REFUSED_UNPROVEN_EQUIVALENCE,
      id,
      "knowledge-hook graph is missing a required property",
      %{predicate: predicate}
    )
  end

  defp ambiguous_property(id, predicate, values) do
    Refusal.new(
      :REFUSED_UNPROVEN_EQUIVALENCE,
      id,
      "knowledge-hook graph has multiple values where one is required",
      %{predicate: predicate, values: Enum.map(values, &term_string/1)}
    )
  end

  defp graph_sha256(statements) do
    statements
    |> Enum.map(fn statement ->
      {subject, predicate, object} = statement3(statement)
      {term_string(subject), term_string(predicate), term_string(object)}
    end)
    |> Enum.sort()
    |> Compiler.sha256()
  end

  defp term_string(term) do
    case term_value(term) do
      value when is_binary(value) -> value
      value -> to_string(value)
    end
  end

  defp term_value(term) do
    if RDF.Term.term?(term), do: RDF.Term.value(term), else: term
  rescue
    _ -> term
  end

  defp normalize_trigger_type(type) when type in [:rdf_change, :sparql_result, :interval, :event], do: type
  defp normalize_trigger_type("RdfChange"), do: :rdf_change
  defp normalize_trigger_type("rdf_change"), do: :rdf_change
  defp normalize_trigger_type("SparqlResult"), do: :sparql_result
  defp normalize_trigger_type("sparql_result"), do: :sparql_result
  defp normalize_trigger_type("Interval"), do: :interval
  defp normalize_trigger_type("interval"), do: :interval
  defp normalize_trigger_type("Event"), do: :event
  defp normalize_trigger_type("event"), do: :event
  defp normalize_trigger_type(_), do: :unsupported

  defp normalize_predicate_type(type) when type in [:ask, :result_delta, :external_trigger], do: type
  defp normalize_predicate_type("ask"), do: :ask
  defp normalize_predicate_type("ASKPredicate"), do: :ask
  defp normalize_predicate_type("result_delta"), do: :result_delta
  defp normalize_predicate_type("ResultDelta"), do: :result_delta
  defp normalize_predicate_type("external_trigger"), do: :external_trigger
  defp normalize_predicate_type(_), do: :unsupported

  defp canonical_definition(hook) do
    %{
      id: hook.id,
      name: hook.name,
      trigger_type: hook.trigger_type,
      trigger_pattern: canonical(hook.trigger_pattern),
      predicate: %{
        type: hook.predicate.type,
        query_sha256: hook.predicate.query_sha256,
        query_form: hook.predicate.query_form,
        query: hook.predicate.query && hook.predicate.query.source
      },
      intent: canonical(hook.intent),
      require_actuation_receipt?: true,
      provenance: canonical(hook.provenance)
    }
  end

  defp projection_definition(hook) do
    canonical_definition(hook)
    |> Map.put(:authority, :UNAUTHORIZED)
    |> Map.put(:standing, :construct_only)
  end

  defp canonical(%_{} = struct), do: struct |> Map.from_struct() |> canonical()

  defp canonical(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, canonical(value)} end)
    |> Enum.sort_by(fn {key, _} -> inspect(key) end)
  end

  defp canonical(list) when is_list(list), do: Enum.map(list, &canonical/1)
  defp canonical(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> Enum.map(&canonical/1)
  defp canonical(value), do: value

  defp ambient_actuation?(map), do: present_ambient_keys(map) != [] or not inert_term?(map)

  defp present_ambient_keys(map) do
    Enum.filter(@ambient_keys, &Map.has_key?(map, &1))
  end

  defp inert_term?(value)
       when is_function(value) or is_pid(value) or is_port(value) or is_reference(value),
       do: false

  defp inert_term?(%_{}), do: false

  defp inert_term?(map) when is_map(map),
    do: Enum.all?(map, fn {key, value} -> inert_term?(key) and inert_term?(value) end)

  defp inert_term?(list) when is_list(list), do: Enum.all?(list, &inert_term?/1)

  defp inert_term?(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.all?(&inert_term?/1)

  defp inert_term?(_), do: true

  defp get(map, key, default \\ nil) when is_map(map) and is_atom(key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end
end

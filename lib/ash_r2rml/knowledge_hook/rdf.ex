# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.RDF do
  @moduledoc """
  Admission adapter for the canonical AshR2RML Knowledge Hook RDF vocabulary.

  The adapter validates the authority/receipt closure encoded by the native
  vocabulary and lowers it into the same `AshR2RML.KnowledgeHooks` plan used by
  map, GitVan, and KNHK inputs. It does not execute constructed targets.
  """

  alias AshR2RML.{Compiler, Refusal}

  @kh "https://seanchatmangpt.github.io/ash-r2rml/knowledge-hook#"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @rdfs_label "http://www.w3.org/2000/01/rdf-schema#label"
  @dct_title "http://purl.org/dc/terms/title"

  @doc "Return true when an RDF graph contains at least one canonical `kh:Hook`."
  def native_hook_graph?(graph) do
    graph
    |> RDF.Data.statements()
    |> Enum.any?(fn statement ->
      {_, predicate, object} = statement3(statement)
      term_string(predicate) == @rdf_type and term_string(object) == @kh <> "Hook"
    end)
  end

  @doc "Parse and admit canonical Knowledge Hook Turtle."
  def from_turtle(turtle, opts \\ []) when is_binary(turtle) and is_list(opts) do
    case RDF.Turtle.read_string(turtle) do
      {:ok, graph} ->
        source_identity =
          Keyword.get(opts, :source_identity, %{})
          |> Map.put_new(:hook_graph_sha256, Compiler.sha256(turtle))
          |> Map.put_new(:hook_vocabulary, @kh)

        from_graph(graph, Keyword.put(opts, :source_identity, source_identity))

      {:error, reason} ->
        {:error,
         [
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :knowledge_hook_turtle,
             "failed to parse canonical Knowledge Hook Turtle",
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
           "canonical Knowledge Hook Turtle parsing raised",
           %{reason: Exception.message(exception)}
         )
       ]}
  end

  @doc "Admit canonical Knowledge Hooks from an RDF graph."
  def from_graph(graph, opts \\ []) when is_list(opts) do
    statements = RDF.Data.statements(graph)
    index = index_statements(statements)
    subjects = subjects_of_type(statements, @kh <> "Hook")

    if subjects == [] do
      {:error,
       [
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hooks,
           "RDF graph contains no canonical AshR2RML Knowledge Hooks",
           %{supported_type: @kh <> "Hook"}
         )
       ]}
    else
      with {:ok, definitions} <- parse_many(subjects, &parse_hook(&1, index)) do
        source_identity =
          Keyword.get(opts, :source_identity, %{})
          |> Map.put_new(:hook_graph_sha256, graph_sha256(statements))
          |> Map.put_new(:hook_vocabulary, @kh)

        AshR2RML.KnowledgeHooks.admit(definitions, source_identity: source_identity)
      end
    end
  rescue
    exception ->
      {:error,
       [
         Refusal.new(
           :REFUSED_UNPROVEN_EQUIVALENCE,
           :knowledge_hook_graph,
           "failed to inspect canonical Knowledge Hook RDF graph",
           %{reason: Exception.message(exception)}
         )
       ]}
  end

  defp parse_hook(subject, index) do
    id = term_string(subject)

    with {:ok, trigger_node} <- required_object(index, subject, @kh <> "trigger", id),
         {:ok, observation_node} <- required_object(index, subject, @kh <> "observation", id),
         {:ok, predicate_node} <- required_object(index, subject, @kh <> "predicate", id),
         {:ok, construct_node} <- required_object(index, subject, @kh <> "construct", id),
         {:ok, receipt_node} <- required_object(index, subject, @kh <> "receiptPolicy", id),
         :ok <- require_construct_ceiling(index, subject, id),
         :ok <- require_receipt_policy(index, receipt_node, id),
         {:ok, trigger_type} <- parse_trigger_type(index, trigger_node, id),
         {:ok, predicate} <- parse_predicate(index, predicate_node, id),
         {:ok, intent} <- parse_construct(index, construct_node, id) do
      name =
        optional_literal(index, subject, @dct_title) ||
          optional_literal(index, subject, @rdfs_label) || id

      dependencies =
        objects(index, subject, @kh <> "after")
        |> Enum.map(&term_string/1)
        |> Enum.uniq()
        |> Enum.sort()

      observation_projection = %{
        node: term_string(observation_node),
        query_sha256: optional_literal(index, observation_node, @kh <> "querySha256")
      }

      {:ok,
       %{
         id: id,
         name: name,
         trigger_type: trigger_type,
         trigger_pattern: optional_literal(index, trigger_node, @kh <> "triggerPattern"),
         predicate: predicate,
         intent: intent,
         require_actuation_receipt?: true,
         provenance: %{
           source: :ash_r2rml_knowledge_hook,
           vocabulary: @kh,
           after: dependencies,
           observation_projection: observation_projection
         }
       }}
    end
  end

  defp require_construct_ceiling(index, subject, id) do
    case objects(index, subject, @kh <> "authorityCeiling") do
      [value] ->
        if term_value(value) == "CONSTRUCT" do
          :ok
        else
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             id,
             "canonical Knowledge Hook authority ceiling must be CONSTRUCT",
             %{authority_ceiling: term_value(value)}
           )}
        end

      [] ->
        {:error, missing_property(id, @kh <> "authorityCeiling")}

      values ->
        {:error, ambiguous_property(id, @kh <> "authorityCeiling", values)}
    end
  end

  defp require_receipt_policy(index, node, id) do
    properties = [
      @kh <> "requiresEvaluationReceipt",
      @kh <> "requiresActuationReceipt",
      @kh <> "requiresConsequenceReceipt"
    ]

    Enum.reduce_while(properties, :ok, fn property, :ok ->
      case objects(index, node, property) do
        [value] ->
          if term_value(value) == true do
            {:cont, :ok}
          else
            {:halt,
             {:error,
              Refusal.new(
                :REFUSED_UNPROVEN_EQUIVALENCE,
                id,
                "canonical Knowledge Hook receipt policy must require every receipt boundary",
                %{property: property, value: term_value(value)}
              )}}
          end

        [] ->
          {:halt, {:error, missing_property(id, property)}}

        values ->
          {:halt, {:error, ambiguous_property(id, property, values)}}
      end
    end)
  end

  defp parse_trigger_type(index, node, id) do
    with {:ok, raw} <- required_literal(index, node, @kh <> "triggerType", id) do
      case raw do
        "rdf_change" -> {:ok, :rdf_change}
        "sparql_result" -> {:ok, :sparql_result}
        "interval" -> {:ok, :interval}
        "event" -> {:ok, :event}
        other ->
          {:error,
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             id,
             "unsupported canonical Knowledge Hook trigger type",
             %{trigger_type: other}
           )}
      end
    end
  end

  defp parse_predicate(index, node, id) do
    with {:ok, type} <- required_literal(index, node, @kh <> "predicateType", id) do
      case type do
        "ask" -> query_predicate(index, node, id, :ask)
        "result_delta" -> query_predicate(index, node, id, :result_delta)
        "external_trigger" -> {:ok, %{type: :external_trigger}}
        other ->
          {:error,
           Refusal.new(
             :REFUSED_UNSUPPORTED_SPARQL_FEATURE,
             id,
             "unsupported canonical Knowledge Hook predicate type",
             %{predicate_type: other}
           )}
      end
    end
  end

  defp query_predicate(index, node, id, type) do
    with {:ok, query} <- required_literal(index, node, @kh <> "queryText", id) do
      {:ok, %{type: type, query: query}}
    end
  end

  defp parse_construct(index, node, id) do
    with {:ok, kind} <- required_literal(index, node, @kh <> "constructKind", id),
         {:ok, target} <- required_literal(index, node, @kh <> "target", id),
         {:ok, normalized_kind} <- construct_kind(kind, id) do
      {:ok, %{kind: normalized_kind, target: target, payload: %{}}}
    end
  end

  defp construct_kind(kind, _id)
       when kind in ["reactor", "ash_action", "state_transition", "oban", "workflow", "pipeline", "opaque_target"],
       do: {:ok, String.to_existing_atom(kind)}

  defp construct_kind(kind, id) do
    {:error,
     Refusal.new(
       :REFUSED_UNPROVEN_EQUIVALENCE,
       id,
       "unsupported canonical Knowledge Hook construct kind",
       %{construct_kind: kind}
     )}
  end

  defp parse_many(subjects, fun) do
    Enum.reduce_while(subjects, {:ok, []}, fn subject, {:ok, acc} ->
      case fun.(subject) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, %Refusal{} = refusal} -> {:halt, {:error, [refusal]}}
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
           "canonical Knowledge Hook property must be a scalar literal",
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

  defp objects(index, subject, predicate) do
    index
    |> Map.get({subject, predicate}, [])
    |> Enum.sort_by(&term_string/1)
  end

  defp missing_property(id, predicate) do
    Refusal.new(
      :REFUSED_UNPROVEN_EQUIVALENCE,
      id,
      "canonical Knowledge Hook graph is missing a required property",
      %{predicate: predicate}
    )
  end

  defp ambiguous_property(id, predicate, values) do
    Refusal.new(
      :REFUSED_UNPROVEN_EQUIVALENCE,
      id,
      "canonical Knowledge Hook graph has multiple values where one is required",
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
end

defmodule AshR2RML.KnowledgeHook.Ingestion do
  @moduledoc "Vocabulary router for canonical AshR2RML, GitVan, and KNHK Knowledge Hook Turtle."

  alias AshR2RML.{KnowledgeHooks, Refusal}
  alias AshR2RML.KnowledgeHook.RDF, as: KnowledgeHookRDF

  @doc "Parse Turtle once, then route it to the native or legacy interoperability admission court."
  def from_turtle(turtle, opts \\ []) when is_binary(turtle) and is_list(opts) do
    case RDF.Turtle.read_string(turtle) do
      {:ok, graph} ->
        if KnowledgeHookRDF.native_hook_graph?(graph) do
          KnowledgeHookRDF.from_graph(graph, opts)
        else
          KnowledgeHooks.from_graph(graph, opts)
        end

      {:error, reason} ->
        {:error,
         [
           Refusal.new(
             :REFUSED_UNPROVEN_EQUIVALENCE,
             :knowledge_hook_turtle,
             "failed to parse Knowledge Hook Turtle",
             %{reason: inspect(reason)}
           )
         ]}
    end
  end
end

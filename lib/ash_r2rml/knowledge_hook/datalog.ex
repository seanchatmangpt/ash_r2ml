# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.Datalog do
  @moduledoc """
  Scoped, hand-written single-rule Datalog evaluator for the `:datalog`
  knowledge-hook predicate type.

  `deps/rdf` (rdf ~> 3.0, verified in-repo via `mix.lock`) has no Datalog
  engine and adding a full external Datalog dependency is a real
  architectural decision this hand-written module deliberately does not make
  unilaterally. This module hand-rolls a bounded subset directly against
  `RDF.Graph.t()` statements, following the same index-and-walk discipline
  `AshR2RML.KnowledgeHook.SHACL` already uses (a `{subject, predicate} =>
  [object]`-shaped index built by folding over statements, joined by simple
  variable-binding substitution).

  ## Scope — read this before using

  This is **NOT a general Datalog engine.** It supports exactly one
  non-recursive rule of the form:

      head(Var1, Var2, ...) :- (S1, P1, O1), (S2, P2, O2), ...

  where each body pattern is a real RDF triple pattern (subject/predicate/
  object), each position is either a variable (`?x`) or a constant IRI
  (`<...>`) or a literal (`"..."`), and body patterns are joined by simple
  nested-loop pattern matching over `opts[:data]` (an `RDF.Graph`, matching
  `:shacl`'s real evaluation target).

  **Explicit, named, unimplemented limits — not silently missing:**

    * **No recursion.** The head predicate may never appear in its own body,
      directly or transitively; there is no fixpoint/stratification
      evaluator here.
    * **No negation.** There is no `NOT`/`\\+` body-pattern form.
    * **No aggregation.** There is no `COUNT`/`SUM`/`MIN`/`MAX` or grouping.
    * **No stratification.** Because there is no recursion or negation,
      there is nothing to stratify — a full engine's stratified evaluation
      order does not exist here.
    * **Single rule only.** `admit_rule/1` admits exactly one rule; there is
      no rule set, no rule dependency graph, no rule ordering.

  A rule that requires any of the above is out of scope for this module and
  must be admitted as `{:error, %AshR2RML.Refusal{}}` (a Blocked verdict at
  the knowledge-hook layer), never silently truncated or best-effort
  evaluated.
  """

  alias AshR2RML.Refusal

  @type term_pattern :: {:var, String.t()} | {:iri, String.t()} | {:literal, String.t()}
  @type triple_pattern :: {term_pattern(), term_pattern(), term_pattern()}

  @type t :: %__MODULE__{
          source: String.t(),
          head_name: String.t(),
          head_vars: [String.t()],
          body: [triple_pattern()]
        }

  @enforce_keys [:source, :head_name, :head_vars, :body]
  defstruct [:source, :head_name, :head_vars, :body]

  @rule_re ~r/\A\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*:-\s*(.+?)\s*\.?\s*\z/s
  @pattern_re ~r/\A\s*\(\s*(.+?)\s*,\s*(.+?)\s*,\s*(.+?)\s*\)\s*\z/

  @doc """
  Admit a single non-recursive Datalog rule of the form
  `head(Vars) :- (S, P, O), (S, P, O), ...` from rule text.

  Refuses (does not raise) on: unparseable rule text, an empty body, a body
  pattern that is not a well-formed triple pattern, a head variable that
  never appears in the body (unsafe), or a head predicate name that appears
  in its own body (recursion — explicitly out of scope, see module doc).
  """
  @spec admit_rule(String.t()) :: {:ok, t()} | {:error, Refusal.t()}
  def admit_rule(rule_text) when is_binary(rule_text) do
    with {:ok, head_name, head_vars_raw, body_raw} <- split_rule(rule_text),
         {:ok, head_vars} <- parse_head_vars(head_vars_raw, rule_text),
         {:ok, body} <- parse_body(body_raw, rule_text),
         :ok <- verify_non_recursive(head_name, body, rule_text),
         :ok <- verify_safe(head_vars, body, rule_text) do
      {:ok, %__MODULE__{source: rule_text, head_name: head_name, head_vars: head_vars, body: body}}
    end
  end

  def admit_rule(other) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_DATALOG_RULE,
       :datalog_predicate,
       "Datalog rule must be text",
       %{got: inspect(other)}
     )}
  end

  @doc """
  Evaluate an admitted single-rule Datalog program against `data` (an
  `RDF.Graph.t()`, or anything `RDF.Data.statements/1` accepts).

  Returns `{:ok, bindings}` where `bindings` is the list of matched head
  bindings (each a map of head variable name => bound term string) —
  `[]` means the rule did not fire (NotFired), a non-empty list means it
  fired (Fired). The third argument is reserved for future evaluation
  options (currently unused, kept for a stable 3-arity call site matching
  `AshR2RML.KnowledgeHook.SHACL.conforms/3`'s shape) and is not inspected.
  """
  @spec evaluate(t() | term(), RDF.Data.Source.t(), keyword()) :: {:ok, [map()]} | {:error, Refusal.t()}
  def evaluate(rule_or_other, data, opts \\ [])

  def evaluate(%__MODULE__{} = rule, data, _opts) do
    index = index_statements(RDF.Data.statements(data))

    bindings =
      rule.body
      |> Enum.reduce([%{}], fn pattern, partial_bindings ->
        Enum.flat_map(partial_bindings, &join_pattern(&1, pattern, index))
      end)
      |> Enum.map(&Map.take(&1, rule.head_vars))
      |> Enum.uniq()

    {:ok, bindings}
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_INVALID_DATALOG_RULE,
         :datalog_predicate,
         "Datalog evaluation raised",
         %{reason: Exception.message(exception)}
       )}
  end

  def evaluate(other, _data, _opts) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_DATALOG_RULE,
       :datalog_predicate,
       "Datalog predicate must be an admitted rule",
       %{got: inspect(other)}
     )}
  end

  # -- rule parsing -------------------------------------------------------

  defp split_rule(rule_text) do
    case Regex.run(@rule_re, rule_text) do
      [_, head_name, head_vars_raw, body_raw] ->
        {:ok, head_name, head_vars_raw, body_raw}

      nil ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_DATALOG_RULE,
           :datalog_predicate,
           "Datalog rule does not match `head(Vars) :- body_pattern1, body_pattern2, ...`",
           %{source: rule_text}
         )}
    end
  end

  defp parse_head_vars(head_vars_raw, rule_text) do
    vars =
      head_vars_raw
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    cond do
      vars == [] ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_DATALOG_RULE,
           :datalog_predicate,
           "Datalog rule head must have at least one variable",
           %{source: rule_text}
         )}

      not Enum.all?(vars, &variable_name?/1) ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_DATALOG_RULE,
           :datalog_predicate,
           "Datalog rule head arguments must all be `?variable` names",
           %{source: rule_text, head_vars: vars}
         )}

      true ->
        {:ok, Enum.map(vars, &String.trim_leading(&1, "?"))}
    end
  end

  defp parse_body(body_raw, rule_text) do
    pattern_texts = split_top_level_patterns(body_raw)

    if pattern_texts == [] do
      {:error,
       Refusal.new(
         :REFUSED_INVALID_DATALOG_RULE,
         :datalog_predicate,
         "Datalog rule body must have at least one triple pattern",
         %{source: rule_text}
       )}
    else
      Enum.reduce_while(pattern_texts, {:ok, []}, fn pattern_text, {:ok, acc} ->
        case parse_pattern(pattern_text, rule_text) do
          {:ok, pattern} -> {:cont, {:ok, [pattern | acc]}}
          {:error, refusal} -> {:halt, {:error, refusal}}
        end
      end)
      |> case do
        {:ok, patterns} -> {:ok, Enum.reverse(patterns)}
        error -> error
      end
    end
  end

  # Splits "(a, b, c), (d, e, f)" into ["(a, b, c)", "(d, e, f)"] by tracking
  # paren depth, since a naive comma-split would also cut the commas inside
  # each triple pattern.
  defp split_top_level_patterns(body_raw) do
    body_raw
    |> String.graphemes()
    |> Enum.reduce({[], "", 0}, fn
      "(", {parts, current, 0} -> {parts, current <> "(", 1}
      "(", {parts, current, depth} -> {parts, current <> "(", depth + 1}
      ")", {parts, current, 1} -> {parts, current <> ")", 0}
      ")", {parts, current, depth} -> {parts, current <> ")", depth - 1}
      ",", {parts, current, 0} -> {[String.trim(current) | parts], "", 0}
      char, {parts, current, depth} -> {parts, current <> char, depth}
    end)
    |> then(fn {parts, current, _depth} ->
      [String.trim(current) | parts]
    end)
    |> Enum.reverse()
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_pattern(pattern_text, rule_text) do
    case Regex.run(@pattern_re, pattern_text) do
      [_, s_raw, p_raw, o_raw] ->
        {:ok, {parse_term(s_raw), parse_term(p_raw), parse_term(o_raw)}}

      nil ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_DATALOG_RULE,
           :datalog_predicate,
           "Datalog body pattern must be `(subject, predicate, object)`",
           %{source: rule_text, pattern: pattern_text}
         )}
    end
  end

  defp parse_term(raw) do
    trimmed = String.trim(raw)

    cond do
      variable_name?(trimmed) ->
        {:var, String.trim_leading(trimmed, "?")}

      String.starts_with?(trimmed, "<") and String.ends_with?(trimmed, ">") ->
        {:iri, String.slice(trimmed, 1..-2//1)}

      String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"") ->
        {:literal, String.slice(trimmed, 1..-2//1)}

      true ->
        {:iri, trimmed}
    end
  end

  defp variable_name?(text), do: String.starts_with?(text, "?") and String.length(text) > 1

  defp verify_non_recursive(head_name, body, rule_text) do
    recursive? =
      Enum.any?(body, fn {s, p, o} ->
        Enum.any?([s, p, o], &match?({:iri, ^head_name}, &1))
      end)

    if recursive? do
      {:error,
       Refusal.new(
         :REFUSED_INVALID_DATALOG_RULE,
         :datalog_predicate,
         "recursive Datalog rules (head predicate appearing in its own body) are out of scope",
         %{source: rule_text, head_name: head_name}
       )}
    else
      :ok
    end
  end

  defp verify_safe(head_vars, body, rule_text) do
    body_vars =
      body
      |> Enum.flat_map(fn {s, p, o} -> [s, p, o] end)
      |> Enum.filter(&match?({:var, _}, &1))
      |> Enum.map(fn {:var, name} -> name end)
      |> MapSet.new()

    unsafe = Enum.reject(head_vars, &MapSet.member?(body_vars, &1))

    if unsafe == [] do
      :ok
    else
      {:error,
       Refusal.new(
         :REFUSED_INVALID_DATALOG_RULE,
         :datalog_predicate,
         "Datalog rule head variable(s) never appear in the body (unsafe rule)",
         %{source: rule_text, unsafe_vars: unsafe}
       )}
    end
  end

  # -- evaluation -----------------------------------------------------------

  defp join_pattern(binding, {s, p, o}, index) do
    s_value = resolve(binding, s)
    p_value = resolve(binding, p)

    case {s_value, p_value} do
      {nil, nil} ->
        for {subj, pred, obj} <- all_triples(index),
            new_binding = bind(bind(bind(binding, s, subj), p, pred), o, obj),
            new_binding != :conflict,
            do: new_binding

      {nil, pv} ->
        for {subj, obj} <- subjects_for_predicate(index, pv),
            new_binding = bind(bind(binding, s, subj), o, obj),
            new_binding != :conflict,
            do: new_binding

      {sv, nil} ->
        for {pred, obj} <- predicates_for_subject(index, sv),
            new_binding = bind(bind(binding, p, pred), o, obj),
            new_binding != :conflict,
            do: new_binding

      {sv, pv} ->
        for obj <- objects(index, sv, pv),
            new_binding = bind(binding, o, obj),
            new_binding != :conflict,
            do: new_binding
    end
  end

  defp resolve(binding, {:var, name}), do: Map.get(binding, name)
  defp resolve(_binding, {:iri, iri}), do: iri
  defp resolve(_binding, {:literal, literal}), do: literal

  defp bind(binding, {:var, name}, value) do
    case Map.fetch(binding, name) do
      {:ok, ^value} -> binding
      {:ok, _other} -> :conflict
      :error -> Map.put(binding, name, value)
    end
  end

  defp bind(binding, {:iri, iri}, value) when value == iri, do: binding
  defp bind(_binding, {:iri, _iri}, _value), do: :conflict
  defp bind(binding, {:literal, literal}, value) when value == literal, do: binding
  defp bind(_binding, {:literal, _literal}, _value), do: :conflict

  defp all_triples(index) do
    for {{subj, pred}, objs} <- index, obj <- objs, do: {subj, pred, obj}
  end

  defp subjects_for_predicate(index, predicate) do
    for {{subj, pred}, objs} <- index, pred == predicate, obj <- objs, do: {subj, obj}
  end

  defp predicates_for_subject(index, subject) do
    for {{subj, pred}, objs} <- index, subj == subject, obj <- objs, do: {pred, obj}
  end

  defp objects(index, subject, predicate), do: Map.get(index, {subject, predicate}, [])

  defp index_statements(statements) do
    Enum.reduce(statements, %{}, fn statement, acc ->
      {subject, predicate, object} = statement3(statement)
      key = {term_string(subject), term_string(predicate)}
      Map.update(acc, key, [term_string(object)], &[term_string(object) | &1])
    end)
  end

  defp statement3({subject, predicate, object}), do: {subject, predicate, object}
  defp statement3({subject, predicate, object, _graph_name}), do: {subject, predicate, object}

  defp term_string(term) when is_binary(term), do: term

  defp term_string(term) do
    if RDF.Term.term?(term), do: to_string(RDF.Term.value(term)), else: to_string(term)
  rescue
    _ -> to_string(term)
  end
end

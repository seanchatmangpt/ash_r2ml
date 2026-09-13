# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.KnowledgeHook.SHACL do
  @moduledoc """
  Scoped, hand-written SHACL Core subset checker for the `:shacl` knowledge-hook
  predicate type.

  `deps/rdf` (rdf ~> 3.0, verified in-repo via `mix.lock`) has no SHACL
  validator, so this module hand-rolls a bounded subset directly against
  `RDF.Data.statements/1` triples, following the same index-and-walk pattern
  `AshR2RML.KnowledgeHooks.from_turtle/2` already uses for GitVan/KNHK Turtle
  parsing (a `{subject, predicate_iri} => [object]` index built by folding over
  statements).

  Supported shape vocabulary (SHACL Core, W3C `sh:` namespace): `sh:targetClass`,
  `sh:targetNode`, `sh:property` (with `sh:path` as a single IRI predicate),
  `sh:minCount`, `sh:maxCount`, `sh:datatype`, `sh:class`, `sh:pattern`.
  Anything else on a shape is ignored rather than refused — this is an
  explicit, named subset, not a full SHACL-Core/SHACL-SPARQL engine.
  """

  alias AshR2RML.Refusal

  @sh "http://www.w3.org/ns/shacl#"
  @rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
  @xsd_string "http://www.w3.org/2001/XMLSchema#string"

  @type violation :: %{
          focus_node: String.t(),
          shape: String.t(),
          path: String.t() | nil,
          constraint: atom(),
          detail: String.t()
        }

  @doc "Admit a SHACL shapes graph from Turtle text or an already-parsed RDF.Graph."
  @spec admit_shapes_graph(RDF.Graph.t() | String.t() | term()) ::
          {:ok, RDF.Graph.t()} | {:error, Refusal.t()}
  def admit_shapes_graph(%RDF.Graph{} = graph), do: {:ok, graph}

  def admit_shapes_graph(turtle) when is_binary(turtle) do
    case RDF.Turtle.read_string(turtle) do
      {:ok, graph} ->
        {:ok, graph}

      {:error, reason} ->
        {:error,
         Refusal.new(
           :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
           :shacl_predicate,
           "failed to parse SHACL shapes graph Turtle",
           %{reason: inspect(reason)}
         )}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
         :shacl_predicate,
         "SHACL shapes graph Turtle parsing raised",
         %{reason: Exception.message(exception)}
       )}
  end

  def admit_shapes_graph(other) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
       :shacl_predicate,
       "SHACL shapes graph must be Turtle text or an RDF.Graph",
       %{got: inspect(other)}
     )}
  end

  @doc """
  Evaluate whether `focus_nodes` conform to every node shape in `shapes_graph`
  that targets them, given `data` (any `RDF.Data.Source.t()`, e.g. an
  `RDF.Graph`) as the data being validated.

  Returns `{:ok, conforms?, violations}` — `conforms?` is `true` (Fired) only
  if every explicitly-supplied focus node satisfies every property shape on
  every node shape whose target selects it, with zero violations. An empty
  `focus_nodes` list is a Blocked condition (no evidence to evaluate), not a
  vacuous pass.
  """
  @spec conforms(RDF.Graph.t(), RDF.Data.Source.t(), [String.t()]) ::
          {:ok, boolean(), [violation()]} | {:error, Refusal.t()}
  def conforms(%RDF.Graph{} = shapes_graph, data, focus_nodes) when is_list(focus_nodes) do
    if focus_nodes == [] do
      {:error,
       Refusal.new(
         :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
         :shacl_predicate,
         "SHACL predicate has no focus node to evaluate",
         %{}
       )}
    else
      shapes = shapes_by_subject(shapes_graph)
      data_index = index_statements(RDF.Data.statements(data))

      violations =
        for {shape, shape_def} <- shapes,
            focus <- focus_nodes,
            targeted?(shape_def, focus, data_index),
            violation <- property_violations(shape, shape_def, data_index, focus),
            do: violation

      {:ok, violations == [], violations}
    end
  rescue
    exception ->
      {:error,
       Refusal.new(
         :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
         :shacl_predicate,
         "SHACL evaluation raised",
         %{reason: Exception.message(exception)}
       )}
  end

  def conforms(other, _data, _focus_nodes) do
    {:error,
     Refusal.new(
       :REFUSED_INVALID_SHACL_SHAPES_GRAPH,
       :shacl_predicate,
       "SHACL shapes graph must be an admitted RDF.Graph",
       %{got: inspect(other)}
     )}
  end

  # -- shapes graph indexing --------------------------------------------------

  defp shapes_by_subject(shapes_graph) do
    index = index_statements(RDF.Data.statements(shapes_graph))

    index
    |> Map.keys()
    |> Enum.filter(fn {_subject, predicate} ->
      predicate in [@sh <> "targetClass", @sh <> "targetNode", @sh <> "property"]
    end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.uniq()
    |> Map.new(fn shape ->
      {shape,
       %{
         target_classes: objects(index, shape, @sh <> "targetClass"),
         target_nodes: objects(index, shape, @sh <> "targetNode"),
         properties: property_shapes(index, shape)
       }}
    end)
  end

  defp property_shapes(index, shape) do
    index
    |> objects(shape, @sh <> "property")
    |> Enum.map(fn property_shape ->
      %{
        path: single(objects(index, property_shape, @sh <> "path")),
        min_count: objects(index, property_shape, @sh <> "minCount") |> single() |> to_integer(),
        max_count: objects(index, property_shape, @sh <> "maxCount") |> single() |> to_integer(),
        datatype: single(objects(index, property_shape, @sh <> "datatype")),
        class: single(objects(index, property_shape, @sh <> "class")),
        pattern: single(objects(index, property_shape, @sh <> "pattern"))
      }
    end)
  end

  # -- targeting ----------------------------------------------------------------

  defp targeted?(%{target_classes: [], target_nodes: []}, _focus, _data_index), do: true

  defp targeted?(%{target_classes: target_classes, target_nodes: target_nodes}, focus, data_index) do
    focus in target_nodes or Enum.any?(target_classes, &has_type?(data_index, focus, &1))
  end

  defp has_type?(data_index, node, class_iri), do: class_iri in objects(data_index, node, @rdf_type)

  # -- constraint evaluation ------------------------------------------------------

  defp property_violations(shape, %{properties: properties}, data_index, focus) do
    Enum.flat_map(properties, fn property_shape ->
      values = if property_shape.path, do: objects(data_index, focus, property_shape.path), else: []
      count = length(values)

      []
      |> min_count_violation(property_shape, shape, focus, count)
      |> max_count_violation(property_shape, shape, focus, count)
      |> datatype_violations(property_shape, shape, focus, values)
      |> class_violations(property_shape, shape, focus, values, data_index)
      |> pattern_violations(property_shape, shape, focus, values)
    end)
  end

  defp min_count_violation(acc, %{min_count: min_count}, shape, focus, count)
       when is_integer(min_count) and count < min_count do
    [violation(shape, focus, nil, :min_count, "expected at least #{min_count} value(s), got #{count}") | acc]
  end

  defp min_count_violation(acc, _property_shape, _shape, _focus, _count), do: acc

  defp max_count_violation(acc, %{max_count: max_count}, shape, focus, count)
       when is_integer(max_count) and count > max_count do
    [violation(shape, focus, nil, :max_count, "expected at most #{max_count} value(s), got #{count}") | acc]
  end

  defp max_count_violation(acc, _property_shape, _shape, _focus, _count), do: acc

  defp datatype_violations(acc, %{datatype: datatype, path: path}, shape, focus, values)
       when is_binary(datatype) do
    bad = Enum.reject(values, &literal_datatype_matches?(&1, datatype))

    if bad == [] do
      acc
    else
      [violation(shape, focus, path, :datatype, "value(s) do not have datatype #{datatype}") | acc]
    end
  end

  defp datatype_violations(acc, _property_shape, _shape, _focus, _values), do: acc

  defp class_violations(acc, %{class: class_iri, path: path}, shape, focus, values, data_index)
       when is_binary(class_iri) do
    bad = Enum.reject(values, &has_type?(data_index, &1, class_iri))

    if bad == [] do
      acc
    else
      [violation(shape, focus, path, :class, "value(s) are not instances of #{class_iri}") | acc]
    end
  end

  defp class_violations(acc, _property_shape, _shape, _focus, _values, _data_index), do: acc

  defp pattern_violations(acc, %{pattern: pattern, path: path}, shape, focus, values)
       when is_binary(pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        bad = Enum.reject(values, &(is_binary(&1) and Regex.match?(regex, &1)))

        if bad == [] do
          acc
        else
          [violation(shape, focus, path, :pattern, "value(s) do not match pattern #{pattern}") | acc]
        end

      {:error, _reason} ->
        [violation(shape, focus, path, :pattern, "shape pattern #{inspect(pattern)} is not a valid regular expression") | acc]
    end
  end

  defp pattern_violations(acc, _property_shape, _shape, _focus, _values), do: acc

  defp violation(shape, focus, path, constraint, detail) do
    %{focus_node: term_string(focus), shape: term_string(shape), path: path && term_string(path), constraint: constraint, detail: detail}
  end

  defp literal_datatype_matches?(value, datatype) when is_binary(value), do: datatype == @xsd_string
  defp literal_datatype_matches?(value, datatype) when is_integer(value),
    do: datatype in ["http://www.w3.org/2001/XMLSchema#integer", "http://www.w3.org/2001/XMLSchema#int"]

  defp literal_datatype_matches?(value, datatype) when is_float(value),
    do: datatype == "http://www.w3.org/2001/XMLSchema#double" or datatype == "http://www.w3.org/2001/XMLSchema#decimal"

  defp literal_datatype_matches?(value, datatype) when is_boolean(value),
    do: datatype == "http://www.w3.org/2001/XMLSchema#boolean"

  defp literal_datatype_matches?(_value, _datatype), do: false

  # -- shared statement indexing (mirrors AshR2RML.KnowledgeHooks) --------------

  defp index_statements(statements) do
    Enum.reduce(statements, %{}, fn statement, acc ->
      {subject, predicate, object} = statement3(statement)
      key = {term_string(subject), term_string(predicate)}
      Map.update(acc, key, [term_value(object)], &[term_value(object) | &1])
    end)
  end

  defp statement3({subject, predicate, object}), do: {subject, predicate, object}
  defp statement3({subject, predicate, object, _graph_name}), do: {subject, predicate, object}

  defp objects(index, subject, predicate) do
    index
    |> Map.get({term_string(subject), predicate}, [])
    |> Enum.sort_by(&term_string/1)
  end

  defp single([value | _]), do: value
  defp single([]), do: nil

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
  defp to_integer(nil), do: nil

  defp term_string(term) when is_binary(term), do: term
  defp term_string(term), do: term_value(term) |> to_string()

  defp term_value(term) do
    if RDF.Term.term?(term), do: RDF.Term.value(term), else: term
  rescue
    _ -> term
  end
end

# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.RDF.GraphAlgebra do
  @moduledoc """
  Pure `RDF.Graph` algebra: add/delete/cleanup/intersection over triple sets.

  Ported from Gno's `Gno.Changeset.Helper` graph-algebra helpers
  (`~/gno/lib/gno/changeset/helper.ex`), stripped of everything that requires a
  live, queryable triple store (Gno's `EffectiveChangeset.Query` SPARQL-CONSTRUCT
  diff-against-store algorithm). AshR2RML has no such store to diff against --
  Ontop is virtual OBDA over Postgres, never a materialized graph -- so this
  module only keeps the store-independent, purely functional half of that
  pattern: combining and subtracting `RDF.Graph.t()` values already held in
  memory (e.g. two successive renders of the same mapping's R2RML Turtle, or two
  successive `AshR2RML.OBDA.InMemory.materialize/3` snapshots).

  No network, no file I/O, no external process -- every function here is a pure
  transformation over `RDF.Graph` structs already in hand.
  """

  alias RDF.Graph

  @doc """
  Merges `addition` into `graph`, returning a new graph with every statement of
  both. Equivalent to `RDF.Graph.add/2` but named to match the changeset-algebra
  vocabulary (`add` as a changeset action, not just a graph operation).
  """
  @spec graph_add(Graph.t(), Graph.t() | nil) :: Graph.t()
  def graph_add(graph, nil), do: graph
  def graph_add(graph, %Graph{} = addition), do: Graph.add(graph, addition)

  @doc """
  Removes every statement of `removal` from `graph`, returning a new graph.
  Subjects left with no statements after removal are dropped entirely (see
  `graph_cleanup/1`), so the result never carries orphaned empty descriptions.
  """
  @spec graph_delete(Graph.t(), Graph.t() | nil) :: Graph.t()
  def graph_delete(graph, nil), do: graph

  def graph_delete(graph, %Graph{} = removal) do
    graph
    |> Graph.delete(removal)
    |> graph_cleanup()
  end

  @doc """
  Drops every subject description that has no statements left, so a graph never
  carries empty `RDF.Description` entries after a deletion.
  """
  @spec graph_cleanup(Graph.t()) :: Graph.t()
  def graph_cleanup(%Graph{} = graph) do
    graph
    |> Graph.descriptions()
    |> Enum.reduce(graph, fn description, acc ->
      if Enum.empty?(description) do
        Graph.delete_descriptions(acc, description.subject)
      else
        acc
      end
    end)
  end

  @doc """
  Returns the statements present in both `left` and `right`, as a new graph.
  Useful for detecting the effective overlap between two mapping-render
  snapshots before deciding whether a regenerated `.ttl` file actually changed.
  """
  @spec graph_intersection(Graph.t(), Graph.t()) :: Graph.t()
  def graph_intersection(%Graph{} = left, %Graph{} = right) do
    right_triples = MapSet.new(right)

    left
    |> Enum.filter(&MapSet.member?(right_triples, &1))
    |> Graph.new()
  end

  @doc """
  True if `graph` and `other` describe exactly the same set of statements
  (order- and blank-node-labeling-independent for ground triples).
  """
  @spec equivalent?(Graph.t(), Graph.t()) :: boolean()
  def equivalent?(%Graph{} = graph, %Graph{} = other) do
    MapSet.new(graph) == MapSet.new(other)
  end
end

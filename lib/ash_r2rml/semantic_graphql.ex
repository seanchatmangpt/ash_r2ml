# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.GraphQL do
  @moduledoc """
  Deterministic, read-only GraphQL projection of admitted `AshR2RML.SemanticIR`.

  GraphQL is a protocol switch, not an authoring surface. `false` emits nothing;
  `true` manufactures one canonical SDL schema plus a semantic manifest directly
  from the admitted IR. There are deliberately no field renames, resolver
  overrides, per-resource exposure switches, mutations, subscriptions, custom
  arguments, or GraphQL-specific authorization rules.

  Applications that need a curated/custom GraphQL product API should use
  `ash_graphql`. This module exists so the semantic plane can expose a stable
  graph-shaped read projection without creating a second configuration or write
  authority plane.

  The generated schema is CONSTRUCT output only. Serving it and resolving reads
  remain runtime concerns. No generated GraphQL surface can mutate canonical or
  foreign state; consequence-bearing operations must re-enter through the
  authorized action/BRCE path.
  """

  alias AshR2RML.{Refusal, SemanticIR}
  alias AshR2RML.SemanticIR.{Attribute, Relationship, Resource}

  @canonical_limit 100

  @type projection :: %{
          schema: String.t(),
          manifest: map(),
          receipt: map()
        }

  @spec compile(SemanticIR.t(), boolean()) ::
          {:ok, projection() | nil} | {:error, Refusal.t()}
  def compile(%SemanticIR{}, false), do: {:ok, nil}

  def compile(%SemanticIR{} = ir, true) do
    resources = Enum.sort_by(ir.resources, & &1.class_iri)
    type_names = allocate_type_names(resources)

    descriptors =
      Enum.map(resources, fn resource ->
        describe_resource(resource, type_names)
      end)

    schema = render_schema(descriptors)
    schema_sha256 = sha256(schema)

    manifest = %{
      protocol: :graphql,
      version: 1,
      source: :semantic_ir,
      mode: :read_only,
      canonical_limit: @canonical_limit,
      mutation_root: false,
      subscription_root: false,
      customization: :unsupported_use_ash_graphql,
      consequence_path: :brce,
      ontology_hash: ir.ontology_hash,
      profile_hash: ir.profile_hash,
      shacl_hash: ir.shacl_hash,
      schema_sha256: schema_sha256,
      resources: Enum.map(descriptors, &manifest_resource/1)
    }

    receipt = %{
      status: :PARTIAL_ALIVE,
      standing: :constructed_read_only_schema,
      protocol: :graphql,
      source: :semantic_ir,
      ontology_hash: ir.ontology_hash,
      profile_hash: ir.profile_hash,
      shacl_hash: ir.shacl_hash,
      schema_sha256: schema_sha256,
      mutation_root: false,
      subscription_root: false,
      authority: :none,
      executed: [],
      verified: [:deterministic_projection],
      blocked: [:runtime_query_execution],
      refusals: []
    }

    {:ok, %{schema: schema, manifest: manifest, receipt: receipt}}
  end

  def compile(%SemanticIR{}, value) do
    {:error,
     Refusal.new(
       :REFUSED_GRAPHQL_CUSTOMIZATION,
       :graphql,
       "ash_r2rml GraphQL is a boolean protocol switch; use ash_graphql for customization",
       %{received: inspect(value), supported: [true, false]}
     )}
  end

  defp describe_resource(%Resource{} = resource, type_names) do
    type_name = Map.fetch!(type_names, resource.class_iri)

    {fields, _used} =
      Enum.reduce(resource.attributes, {[], MapSet.new(["iri"])}, fn attribute, {fields, used} ->
        field = attribute_field(attribute, used)
        {[field | fields], MapSet.put(used, field.name)}
      end)

    {fields, _used} =
      Enum.reduce(resource.relationships, {fields, field_names(fields)}, fn relationship, {fields, used} ->
        field = relationship_field(relationship, type_names, used)
        {[field | fields], MapSet.put(used, field.name)}
      end)

    fields = Enum.sort_by(fields, & &1.name)
    query_name = graphql_field_name(type_name)

    %{
      class_iri: resource.class_iri,
      shape_iri: resource.shape_iri,
      type_name: type_name,
      query_name: query_name,
      list_query_name: query_name <> "_list",
      fields: fields
    }
  end

  defp attribute_field(%Attribute{} = attribute, used) do
    base = attribute.predicate_iri |> iri_local_name() |> graphql_field_name()
    name = unique_name(base, attribute.predicate_iri, used)

    %{
      name: name,
      kind: :datatype_property,
      predicate_iri: attribute.predicate_iri,
      target_class: nil,
      graphql_type: cardinality_type(attribute_graphql_type(attribute), attribute.min_count, attribute.max_count)
    }
  end

  defp relationship_field(%Relationship{} = relationship, type_names, used) do
    base = relationship.predicate_iri |> iri_local_name() |> graphql_field_name()
    name = unique_name(base, relationship.predicate_iri, used)
    target_type = Map.fetch!(type_names, relationship.target_class)

    %{
      name: name,
      kind: :object_property,
      predicate_iri: relationship.predicate_iri,
      target_class: relationship.target_class,
      graphql_type: cardinality_type(target_type, relationship.min_count, relationship.max_count)
    }
  end

  defp render_schema(descriptors) do
    scalar_names =
      descriptors
      |> Enum.flat_map(& &1.fields)
      |> Enum.map(&base_type/1)
      |> Enum.filter(&(&1 in ["BigInt", "Date", "DateTime", "Decimal", "JSON"]))
      |> Enum.uniq()
      |> Enum.sort()

    scalars = Enum.map(scalar_names, &"scalar #{&1}")
    types = Enum.map(descriptors, &render_type/1)
    query = render_query(descriptors)

    (scalars ++ types ++ [query, "schema {\n  query: Query\n}"])
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp render_type(descriptor) do
    fields =
      [%{name: "iri", graphql_type: "ID!"} | descriptor.fields]
      |> Enum.map_join("\n", fn field -> "  #{field.name}: #{field.graphql_type}" end)

    "type #{descriptor.type_name} {\n#{fields}\n}"
  end

  defp render_query(descriptors) do
    body =
      descriptors
      |> Enum.flat_map(fn descriptor ->
        [
          "  #{descriptor.query_name}(iri: ID!): #{descriptor.type_name}",
          "  #{descriptor.list_query_name}(limit: Int = #{@canonical_limit}, offset: Int = 0): [#{descriptor.type_name}!]!"
        ]
      end)
      |> Enum.join("\n")

    "type Query {\n#{body}\n}"
  end

  defp manifest_resource(descriptor) do
    %{
      class_iri: descriptor.class_iri,
      shape_iri: descriptor.shape_iri,
      graphql_type: descriptor.type_name,
      query: descriptor.query_name,
      list_query: descriptor.list_query_name,
      fields:
        Enum.map(descriptor.fields, fn field ->
          %{
            graphql_field: field.name,
            graphql_type: field.graphql_type,
            semantic_kind: field.kind,
            predicate_iri: field.predicate_iri,
            target_class: field.target_class
          }
        end)
    }
  end

  defp allocate_type_names(resources) do
    Enum.reduce(resources, {%{}, MapSet.new()}, fn resource, {names, used} ->
      base = resource.class_iri |> iri_local_name() |> graphql_type_name()
      name = unique_name(base, resource.class_iri, used)
      {Map.put(names, resource.class_iri, name), MapSet.put(used, name)}
    end)
    |> elem(0)
  end

  defp field_names(fields), do: fields |> Enum.map(& &1.name) |> MapSet.new() |> MapSet.put("iri")

  defp unique_name(base, semantic_iri, used) do
    if MapSet.member?(used, base) do
      base <> "_" <> String.slice(sha256(semantic_iri), 0, 8)
    else
      base
    end
  end

  defp iri_local_name(value) when is_binary(value) do
    value
    |> String.split(["#", "/", ":"], trim: true)
    |> List.last()
    |> case do
      nil -> "SemanticValue"
      "" -> "SemanticValue"
      local -> local
    end
  end

  defp graphql_type_name(value) do
    value
    |> sanitize_name()
    |> Macro.camelize()
    |> ensure_graphql_name("T")
  end

  defp graphql_field_name(value) do
    value
    |> sanitize_name()
    |> Macro.underscore()
    |> ensure_graphql_name("f_")
  end

  defp sanitize_name(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_]+/u, "_")
    |> String.trim("_")
    |> case do
      "" -> "semantic_value"
      sanitized -> sanitized
    end
  end

  defp ensure_graphql_name("__" <> _ = value, prefix), do: prefix <> value

  defp ensure_graphql_name(value, prefix) do
    if Regex.match?(~r/^[A-Za-z_]/, value), do: value, else: prefix <> value
  end

  defp attribute_graphql_type(%Attribute{identity?: true}), do: "ID"
  defp attribute_graphql_type(%Attribute{ash_type: :uuid}), do: "ID"
  defp attribute_graphql_type(%Attribute{ash_type: :boolean}), do: "Boolean"
  defp attribute_graphql_type(%Attribute{ash_type: :float}), do: "Float"
  defp attribute_graphql_type(%Attribute{ash_type: :integer}), do: "BigInt"
  defp attribute_graphql_type(%Attribute{ash_type: :decimal}), do: "Decimal"
  defp attribute_graphql_type(%Attribute{ash_type: :date}), do: "Date"
  defp attribute_graphql_type(%Attribute{ash_type: type}) when type in [:utc_datetime, :utc_datetime_usec], do: "DateTime"
  defp attribute_graphql_type(%Attribute{ash_type: :string}), do: "String"
  defp attribute_graphql_type(_), do: "JSON"

  defp cardinality_type(type, min_count, 1) do
    if min_count > 0, do: type <> "!", else: type
  end

  defp cardinality_type(type, min_count, _max_count) do
    list = "[#{type}!]"
    if min_count > 0, do: list <> "!", else: list
  end

  defp base_type(%{graphql_type: graphql_type}) do
    graphql_type
    |> String.replace(["[", "]", "!"], "")
  end

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

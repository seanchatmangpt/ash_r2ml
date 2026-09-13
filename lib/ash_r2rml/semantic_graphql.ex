# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Semantic.GraphQL do
  @moduledoc """
  Deterministic, read-only GraphQL projection of admitted `AshR2RML.SemanticIR`.

  GraphQL is a protocol switch, not an authoring surface. `false` emits nothing;
  `true` manufactures one canonical SDL schema plus a semantic manifest directly
  from the admitted IR. There are no field renames, resolver overrides,
  per-resource exposure switches, mutations, subscriptions, custom arguments,
  or GraphQL-specific authorization rules.

  DfCM is preserved at the runtime boundary: this compiler does not choose or
  own a query-serving backend. It manufactures a collision-safe read contract;
  runtime execution remains an external consumer choice and carries no ambient
  authority from this projection.

  Actions and authorization policies are preserved as manifest obligations but
  are deliberately not projected into GraphQL execution. This prevents a
  read-protocol projection from silently erasing incumbent consequence or policy
  semantics while keeping all enforcement and DO authority outside this plane.

  Use `ash_graphql` when a curated/custom GraphQL application API is required.
  This projection is CONSTRUCT-only and grants no DO authority.
  """

  alias AshR2RML.{Refusal, SemanticIR}
  alias AshR2RML.SemanticIR.{Attribute, Relationship, Resource}

  @canonical_limit 100
  @custom_scalars ~w(BigInt Date DateTime Decimal JSON)
  @reserved_types MapSet.new(~w(Query Mutation Subscription String Int Float Boolean ID BigInt Date DateTime Decimal JSON))

  @type projection :: %{schema: String.t(), manifest: map(), receipt: map()}

  @spec compile(SemanticIR.t(), boolean()) :: {:ok, projection() | nil} | {:error, Refusal.t()}
  def compile(%SemanticIR{}, false), do: {:ok, nil}

  def compile(%SemanticIR{} = ir, true) do
    resources = Enum.sort_by(ir.resources, & &1.class_iri)
    type_names = allocate_type_names(resources)
    query_names = allocate_query_names(resources, type_names)
    descriptors = Enum.map(resources, &describe_resource(&1, type_names, query_names))
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
      action_projection: false,
      authority: :none,
      customization: :unsupported_use_ash_graphql,
      consequence_path: :brce,
      policy_enforcement: :external,
      runtime_execution: :external,
      backend_selection: :unselected,
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
      action_projection: false,
      policy_enforcement: :external,
      authority: :none,
      observed: [],
      executed: [],
      verified: [],
      declared: [:deterministic_projection, :query_only, :no_do_authority],
      blocked: [],
      unsupported: [:runtime_query_execution, :runtime_policy_enforcement],
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

  defp describe_resource(%Resource{} = resource, type_names, query_names) do
    type_name = Map.fetch!(type_names, resource.class_iri)
    {query_name, list_query_name} = Map.fetch!(query_names, resource.class_iri)

    {attribute_fields, used} =
      Enum.reduce(resource.attributes, {[], MapSet.new(["iri"])}, fn attribute, {fields, used} ->
        field = attribute_field(attribute, used)
        {[field | fields], MapSet.put(used, field.name)}
      end)

    {fields, _used} =
      Enum.reduce(resource.relationships, {attribute_fields, used}, fn relationship, {fields, used} ->
        field = relationship_field(relationship, type_names, used)
        {[field | fields], MapSet.put(used, field.name)}
      end)

    %{
      class_iri: resource.class_iri,
      shape_iri: resource.shape_iri,
      type_name: type_name,
      query_name: query_name,
      list_query_name: list_query_name,
      fields: Enum.sort_by(fields, & &1.name),
      actions: Enum.sort_by(resource.actions, &{to_string(&1.name), to_string(&1.kind)}),
      policies: Enum.sort_by(resource.policies, &{to_string(&1.name), to_string(&1.effect)})
    }
  end

  defp attribute_field(%Attribute{} = attribute, used) do
    name = semantic_field_name(attribute.predicate_iri, used)

    %{
      name: name,
      kind: :datatype_property,
      predicate_iri: attribute.predicate_iri,
      target_class: nil,
      graphql_type: cardinality_type(attribute_graphql_type(attribute), attribute.min_count, attribute.max_count)
    }
  end

  defp relationship_field(%Relationship{} = relationship, type_names, used) do
    name = semantic_field_name(relationship.predicate_iri, used)
    target_type = Map.fetch!(type_names, relationship.target_class)

    %{
      name: name,
      kind: :object_property,
      predicate_iri: relationship.predicate_iri,
      target_class: relationship.target_class,
      graphql_type: cardinality_type(target_type, relationship.min_count, relationship.max_count)
    }
  end

  defp semantic_field_name(predicate_iri, used) do
    predicate_iri
    |> iri_local_name()
    |> graphql_field_name()
    |> unique_name(predicate_iri, used)
  end

  defp render_schema(descriptors) do
    scalars =
      descriptors
      |> Enum.flat_map(& &1.fields)
      |> Enum.map(&base_type(&1.graphql_type))
      |> Enum.filter(&(&1 in @custom_scalars))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.map(&"scalar #{&1}")

    types = Enum.map(descriptors, &render_type/1)
    query = render_query(descriptors)

    (scalars ++ types ++ [query, "schema {\n  query: Query\n}"])
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  defp render_type(descriptor) do
    fields =
      [%{name: "iri", graphql_type: "ID!"} | descriptor.fields]
      |> Enum.map_join("\n", &"  #{&1.name}: #{&1.graphql_type}")

    "type #{descriptor.type_name} {\n#{fields}\n}"
  end

  defp render_query([]), do: "type Query {\n  _semantic_empty: Boolean\n}"

  defp render_query(descriptors) do
    body =
      Enum.flat_map(descriptors, fn descriptor ->
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
        end),
      excluded_consequence_actions: Enum.map(descriptor.actions, &manifest_action/1),
      policy_obligations: Enum.map(descriptor.policies, &manifest_policy/1)
    }
  end

  defp manifest_action(action) do
    %{
      name: action.name,
      kind: action.kind,
      projected: false,
      consequence_path: :brce
    }
  end

  defp manifest_policy(policy) do
    %{
      name: policy.name,
      effect: policy.effect,
      odrl_iri: policy.odrl_iri,
      enforcement: :external,
      source: :semantic_ir
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

  defp allocate_query_names(resources, type_names) do
    Enum.reduce(resources, {%{}, MapSet.new()}, fn resource, {names, used} ->
      base = type_names |> Map.fetch!(resource.class_iri) |> graphql_field_name()
      {query_name, used} = allocate_root_name(base, resource.class_iri <> "#query", used)
      {list_query_name, used} = allocate_root_name(base <> "_list", resource.class_iri <> "#list", used)

      {Map.put(names, resource.class_iri, {query_name, list_query_name}), used}
    end)
    |> elem(0)
  end

  defp allocate_root_name(base, semantic_key, used) do
    name = unique_name(base, semantic_key, used)
    {name, MapSet.put(used, name)}
  end

  defp unique_name(base, semantic_iri, used) do
    if MapSet.member?(used, base), do: unique_suffix(base, semantic_iri, used, 0), else: base
  end

  defp unique_suffix(base, semantic_iri, used, attempt) do
    candidate = base <> "_" <> String.slice(sha256("#{semantic_iri}:#{attempt}"), 0, 8)
    if MapSet.member?(used, candidate), do: unique_suffix(base, semantic_iri, used, attempt + 1), else: candidate
  end

  defp iri_local_name(value) when is_binary(value) do
    case value |> String.split(["#", "/", ":"], trim: true) |> List.last() do
      nil -> "SemanticValue"
      "" -> "SemanticValue"
      local -> local
    end
  end

  defp graphql_type_name(value) do
    name = value |> sanitize_name() |> Macro.camelize() |> ensure_graphql_name("T")
    if MapSet.member?(@reserved_types, name), do: "Semantic" <> name, else: name
  end

  defp graphql_field_name(value) do
    value |> sanitize_name() |> Macro.underscore() |> ensure_graphql_name("f_")
  end

  defp sanitize_name(value) do
    case value |> to_string() |> String.replace(~r/[^A-Za-z0-9_]+/u, "_") |> String.trim("_") do
      "" -> "semantic_value"
      sanitized -> sanitized
    end
  end

  defp ensure_graphql_name("__" <> _ = value, prefix), do: prefix <> value
  defp ensure_graphql_name(value, prefix), do: if(Regex.match?(~r/^[A-Za-z_]/, value), do: value, else: prefix <> value)

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

  defp cardinality_type(type, min_count, 1), do: if(min_count > 0, do: type <> "!", else: type)

  defp cardinality_type(type, min_count, _max_count) do
    list = "[#{type}!]"
    if min_count > 0, do: list <> "!", else: list
  end

  defp base_type(graphql_type), do: String.replace(graphql_type, ~r/[\[\]!]/, "")
  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end

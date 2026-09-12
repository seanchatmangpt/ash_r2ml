# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshGraphql.Resource) do
  defmodule AshR2RML.Graphql.MutationLeakError do
    @moduledoc "Raised when a supposedly read-only projected schema exposes a mutation root."
    defexception [:message]
  end

  defmodule AshR2RML.Graphql.Schema do
    @moduledoc """
    `use`-able Absinthe schema base for the query-only R2RML projection.

        defmodule MyApp.Schema do
          use AshR2RML.Graphql.Schema, domains: [MyApp.Domain]
        end

    The generated AST contains no `mutation` and no `subscription` token, so
    `AshGraphql.mutation/1` is never invoked and `RootMutationType` is never
    defined. A `r2rml_schema_sha` field is added to the Query root, which both
    guarantees a non-empty Query type and lets a client verify the schema it is
    talking to.
    """

    defmacro __using__(opts) do
      domains = Keyword.get(opts, :domains, [])

      quote location: :keep do
        use Absinthe.Schema
        use AshGraphql, domains: unquote(domains)

        @doc false
        def __r2rml_domains__, do: unquote(domains)

        query do
          field :r2rml_schema_sha, non_null(:string) do
            resolve(fn _, _, _ ->
              {:ok, AshR2RML.Graphql.Schema.schema_sha(__MODULE__)}
            end)
          end
        end
      end
    end

    @doc "Raw SDL for `schema`."
    def sdl(schema), do: Absinthe.Schema.to_sdl(schema)

    @doc """
    SDL normalized to a canonical byte form: top-level definition blocks sorted
    by their text, trailing whitespace stripped.
    """
    def canonical_sdl(schema) do
      schema
      |> sdl()
      |> String.split(~r/\n(?=(?:type|input|enum|interface|union|scalar|schema|directive)\s)/)
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.sort()
      |> Enum.join("\n\n")
      |> Kernel.<>("\n")
    end

    @doc """
    SHA-256 of `canonical_sdl/1`, after asserting the schema is really read-only.
    """
    def schema_sha(schema) do
      sdl = sdl(schema)
      assert_read_only!(schema, sdl)

      :crypto.hash(:sha256, canonical_sdl(schema)) |> Base.encode16(case: :lower)
    end

    @doc """
    Machine-consumable receipt for `schema`.
    """
    def receipt(schema) do
      resources =
        schema
        |> resources()
        |> Enum.sort()

      queries =
        Enum.flat_map(resources, fn resource ->
          resource
          |> AshR2RML.Graphql.Info.derived_queries()
          |> Enum.map(&%{resource: resource, name: &1.name, type: &1.type, action: &1.action})
        end)

      %{
        schema: schema,
        resources: resources,
        queries: queries,
        mutation_root: nil,
        subscription_root: nil,
        sdl_bytes: byte_size(canonical_sdl(schema)),
        sha256: schema_sha(schema)
      }
    end

    defp resources(schema) do
      Code.ensure_loaded?(schema)

      if function_exported?(schema, :__r2rml_domains__, 0) do
        schema.__r2rml_domains__()
        |> Enum.flat_map(&Ash.Domain.Info.resources/1)
        |> Enum.filter(&(AshR2RML.Graphql in Spark.extensions(&1)))
        |> Enum.uniq()
      else
        []
      end
    end

    defp assert_read_only!(schema, sdl) do
      cond do
        Absinthe.Schema.lookup_type(schema, :mutation) != nil ->
          raise AshR2RML.Graphql.MutationLeakError,
                "#{inspect(schema)} exposes a mutation root type; the R2RML GraphQL " <>
                  "projection must be read-only."

        String.contains?(sdl, "type RootMutationType") ->
          raise AshR2RML.Graphql.MutationLeakError,
                "#{inspect(schema)} SDL contains type RootMutationType; the R2RML " <>
                  "GraphQL projection must be read-only."

        true ->
          :ok
      end
    end
  end
end

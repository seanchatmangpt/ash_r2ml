# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshGraphql.Resource) do
  defmodule AshR2RML.Graphql do
    @moduledoc """
    Query-only GraphQL projection for R2RML-mapped Ash resources.

    Adding this extension to a resource is the entire configuration surface: its
    presence means "project this resource's public `:read` actions as GraphQL
    queries". No mutations or subscriptions are ever constructed, and declaring
    them on a projected resource is refused at compile time by
    `AshR2RML.Graphql.Verifiers.NoMutations`.

        defmodule MyApp.Person do
          use Ash.Resource,
            domain: MyApp.Domain,
            data_layer: AshPostgres.DataLayer,
            extensions: [AshR2RML.Resource, AshR2RML.Graphql]
        end

    The consumer never lists `AshGraphql.Resource` (it is pulled in via
    `add_extensions:`) and never writes a `graphql do ... end` block.
    """

    alias AshR2RML.Graphql.Schema, as: ProjectionSchema

    @r2rml_graphql %Spark.Dsl.Section{
      name: :r2rml_graphql,
      describe: "On/off switch for the R2RML GraphQL read projection. No other options exist by design.",
      schema: [
        enabled?: [
          type: :boolean,
          default: true,
          doc: "Set false to suppress the projection."
        ]
      ]
    }

    use Spark.Dsl.Extension,
      sections: [@r2rml_graphql],
      transformers: [AshR2RML.Graphql.Transformers.DeriveQueries],
      verifiers: [AshR2RML.Graphql.Verifiers.NoMutations],
      add_extensions: [AshGraphql.Resource]

    @doc """
    Machine-consumable receipt for a projected Absinthe schema module.

    See `AshR2RML.Graphql.Schema.receipt/1`.
    """
    def receipt(schema), do: ProjectionSchema.receipt(schema)
  end
end

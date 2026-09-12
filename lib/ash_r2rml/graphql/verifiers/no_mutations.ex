# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshGraphql.Resource) do
  defmodule AshR2RML.Graphql.Verifiers.NoMutations do
    @moduledoc """
    Refuses, at compile time, any GraphQL mutation or subscription declared on a
    resource that carries `AshR2RML.Graphql`.
    """

    use Spark.Dsl.Verifier

    alias Spark.Dsl.Verifier
    alias Spark.Error.DslError

    @doc false
    def verify(dsl) do
      Enum.reduce_while([:mutations, :subscriptions], :ok, fn key, _ ->
        case Verifier.get_entities(dsl, [:graphql, key]) do
          [] ->
            {:cont, :ok}

          nil ->
            {:cont, :ok}

          _ ->
            {:halt,
             {:error,
              DslError.exception(
                module: Verifier.get_persisted(dsl, :module),
                path: [:graphql, key],
                message:
                  "AshR2RML.Graphql is a read-only projection; declaring GraphQL " <>
                    "mutations/subscriptions on an R2RML-projected resource is refused. " <>
                    "Remove the block or remove AshR2RML.Graphql."
              )}}
        end
      end)
    end
  end
end

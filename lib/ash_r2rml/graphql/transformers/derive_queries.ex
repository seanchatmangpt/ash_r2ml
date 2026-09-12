# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshGraphql.Resource) do
  defmodule AshR2RML.Graphql.Transformers.DeriveQueries do
    @moduledoc """
    Derives `%AshGraphql.Resource.Query{}` entities from the resource's public
    `:read` actions and writes them into `[:graphql, :queries]`.

    Deterministic and collision-free by construction: actions are sorted by name
    and the query names are pure string concatenations over
    `Ash.Resource.Info.short_name/1`.
    """

    use Spark.Dsl.Transformer

    alias Spark.Dsl.Transformer

    @doc false
    def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
    def after?(_), do: false

    @doc false
    def before?(AshGraphql.Resource.Transformers.ValidateActions), do: true
    def before?(AshGraphql.Resource.Transformers.FlattenQueryMutationGroups), do: true
    def before?(AshGraphql.Resource.Transformers.RequireKeysetForRelayQueries), do: true
    def before?(AshGraphql.Resource.Transformers.ValidateCompatibleNames), do: true
    def before?(_), do: false

    @doc false
    def transform(dsl) do
      cond do
        Transformer.get_persisted(dsl, :module) == nil -> {:ok, dsl}
        not resource?(dsl) -> {:ok, dsl}
        not AshR2RML.Graphql.Info.enabled?(dsl) -> {:ok, dsl}
        true -> {:ok, project(dsl)}
      end
    end

    defp resource?(dsl) do
      Transformer.get_entities(dsl, [:actions]) != []
    end

    defp project(dsl) do
      singular = Ash.Resource.Info.short_name(dsl)
      plural = :"#{singular}s"

      dsl =
        case Transformer.get_option(dsl, [:graphql], :type) do
          nil -> Transformer.set_option(dsl, [:graphql], :type, singular)
          _ -> dsl
        end

      dsl
      |> read_actions()
      |> Enum.flat_map(&queries_for(&1, singular, plural))
      |> Enum.reduce(dsl, fn query, acc ->
        Transformer.add_entity(acc, [:graphql, :queries], query)
      end)
    end

    defp read_actions(dsl) do
      dsl
      |> Ash.Resource.Info.actions()
      |> Enum.filter(&(&1.type == :read and &1.public?))
      |> Enum.sort_by(& &1.name)
    end

    defp queries_for(action, singular, plural) do
      cond do
        Map.get(action, :primary?) ->
          [
            query(type: :get, name: singular, action: action.name, allow_nil?: true),
            query(
              type: :list,
              name: plural,
              action: action.name,
              paginate_with: paginate_with(action)
            )
          ]

        Map.get(action, :get?) ->
          [
            query(
              type: :get,
              name: :"#{singular}_#{action.name}",
              action: action.name,
              allow_nil?: true
            )
          ]

        true ->
          [
            query(
              type: :list,
              name: :"#{plural}_#{action.name}",
              action: action.name,
              paginate_with: paginate_with(action)
            )
          ]
      end
    end

    defp query(fields) do
      struct(AshGraphql.Resource.Query, Keyword.put_new(fields, :identity, nil))
    end

    defp paginate_with(%{pagination: pagination}) when not is_map(pagination), do: nil
    defp paginate_with(%{pagination: %{keyset?: true}}), do: :keyset
    defp paginate_with(%{pagination: %{offset?: true}}), do: :offset
    defp paginate_with(_), do: nil
  end
end

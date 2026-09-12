# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshGraphql.Resource) do
  defmodule AshR2RML.Graphql.Info do
    @moduledoc """
    Introspection for the `AshR2RML.Graphql` projection.
    """

    alias AshGraphql.Resource.Info, as: GraphqlInfo
    alias Spark.Dsl.Extension

    @doc """
    Whether the projection is enabled for `resource`.

    Returns `false` when either the resource or its domain sets
    `r2rml_graphql.enabled? false`.
    """
    def enabled?(resource) do
      resource_enabled?(resource) and domain_enabled?(resource)
    end

    defp resource_enabled?(dsl_or_module) do
      Extension.get_opt(dsl_or_module, [:r2rml_graphql], :enabled?, true)
    end

    defp domain_enabled?(dsl_or_module) do
      case domain(dsl_or_module) do
        nil -> true
        domain -> domain_opt_enabled?(domain)
      end
    end

    # The domain may not be a compiled Spark DSL module at the time a resource's
    # transformers run -- e.g. a fixture that defines the domain *after* the
    # resources in the same file, in which case `Extension.get_opt/4` raises
    # "... is not a Spark DSL module". Absent a readable opt-out the answer is the
    # schema default (`true`), which is what an unset `enabled?` means anyway.
    defp domain_opt_enabled?(domain) do
      resource_enabled?(domain)
    rescue
      _ -> true
    end

    defp domain(dsl_or_module) do
      Ash.Resource.Info.domain(dsl_or_module)
    rescue
      _ -> nil
    end

    @doc """
    The queries derived by `AshR2RML.Graphql.Transformers.DeriveQueries`,
    sorted by name.
    """
    def derived_queries(resource) do
      resource
      |> GraphqlInfo.queries()
      |> Enum.sort_by(& &1.name)
    end
  end
end

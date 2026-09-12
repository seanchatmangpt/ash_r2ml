# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real fixture for the `AshR2RML.Graphql` query-only projection. `Ash.DataLayer.Ets`
# so a real `Absinthe.run/2` query can execute against real stored rows with no
# external database. The resource deliberately declares `:create` and `:update`
# actions alongside `:read` -- the projection must NOT turn those into mutation
# fields.

defmodule AshR2RML.GraphqlProjection.Domain do
  @moduledoc "Real `Ash.Domain` scoping the GraphQL projection fixture."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.GraphqlProjection.Person
  end
end

defmodule AshR2RML.GraphqlProjection.Person do
  @moduledoc """
  R2RML-mapped resource projected read-only into GraphQL by `AshR2RML.Graphql`.
  """
  use Ash.Resource,
    domain: AshR2RML.GraphqlProjection.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML, AshR2RML.Graphql]

  ets do
    private? true
  end

  r2rml do
    class_iri("http://xmlns.com/foaf/0.1/Person")
    subject_template("https://example.org/people/{id}")
    table_name("graphql_projection_people")

    attribute_mappings([
      {:name, "http://xmlns.com/foaf/0.1/name"}
    ])
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]
  end
end

defmodule AshR2RML.GraphqlProjection.Schema do
  @moduledoc "Real Absinthe schema built from the query-only projection."
  use AshR2RML.Graphql.Schema, domains: [AshR2RML.GraphqlProjection.Domain]
end

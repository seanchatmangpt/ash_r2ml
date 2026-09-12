# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real fixtures for the ZERO-CONSUMER-SURFACE auto projection. Neither resource
# below names `AshR2RML.Graphql` or `AshGraphql.Resource`, and neither writes a
# `graphql do ... end` block: the entire declaration is `extensions: [AshR2RML]`
# or `extensions: [AshR2RML.Resource]`. Both must still get a working query-only
# GraphQL projection via `add_extensions:`.
#
# `Ash.DataLayer.Ets` so real `Absinthe.run/2` queries execute against real
# stored rows with no external database. Both resources deliberately declare
# `:create`/`:update` actions -- the projection must NOT turn those into
# mutation fields.

defmodule AshR2RML.GraphqlAutoProjection.Domain do
  @moduledoc "Real `Ash.Domain` scoping the implicit-projection fixtures."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource AshR2RML.GraphqlAutoProjection.Robot
    resource AshR2RML.GraphqlAutoProjection.Drone
  end
end

defmodule AshR2RML.GraphqlAutoProjection.Robot do
  @moduledoc """
  Declares ONLY `AshR2RML.Resource` -- the extension under test for the implicit
  path. No `AshR2RML.Graphql`, no `AshGraphql.Resource`, no `graphql` block.
  """
  use Ash.Resource,
    domain: AshR2RML.GraphqlAutoProjection.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML.Resource]

  ets do
    private? true
  end

  r2rml do
    table_name("graphql_auto_projection_robots")
    class("https://example.org/ns#Robot")

    subject do
      template("https://example.org/robots/{id}")
    end

    property(:name, "https://example.org/ns#name")
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]
  end
end

defmodule AshR2RML.GraphqlAutoProjection.Drone do
  @moduledoc """
  Declares ONLY `AshR2RML` (the public extension every other fixture in this repo
  uses) -- the implicit path must hold for it identically.
  """
  use Ash.Resource,
    domain: AshR2RML.GraphqlAutoProjection.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  ets do
    private? true
  end

  r2rml do
    class_iri("https://example.org/ns#Drone")
    subject_template("https://example.org/drones/{id}")
    table_name("graphql_auto_projection_drones")

    attribute_mappings([
      {:name, "https://example.org/ns#name"}
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

defmodule AshR2RML.GraphqlAutoProjection.Schema do
  @moduledoc "Real Absinthe schema built entirely from implicitly-projected resources."
  use AshR2RML.Graphql.Schema, domains: [AshR2RML.GraphqlAutoProjection.Domain]
end

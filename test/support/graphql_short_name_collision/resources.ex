# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Real falsifier for the short-name-collision path: two resources in different
# namespaces whose module names both end in `Widget` -- neither sets `resource
# short_name: ...`, so `Ash.Resource.Info.short_name/1` falls back to
# `default_short_name/0` (last module segment, underscored) for both, and
# `AshR2RML.Graphql.Transformers.DeriveQueries.derive_type/1` derives the same
# `:widget` GraphQL type/query names for both when they share one schema.

defmodule AshR2RML.ShortNameCollision.NsA.Widget do
  @moduledoc "First `Widget` resource; namespace NsA."
  use Ash.Resource,
    domain: AshR2RML.ShortNameCollision.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  ets do
    private?(true)
  end

  r2rml do
    class_iri("https://example.org/ns#WidgetA")
    subject_template("https://example.org/ns-a/widgets/{id}")
    table_name("short_name_collision_ns_a_widgets")
    attribute_mappings([{:name, "https://example.org/ns#name"}])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, create: [:name], update: [:name]])
  end
end

defmodule AshR2RML.ShortNameCollision.NsB.Widget do
  @moduledoc "Second `Widget` resource; namespace NsB. Same default short name as NsA.Widget."
  use Ash.Resource,
    domain: AshR2RML.ShortNameCollision.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshR2RML]

  ets do
    private?(true)
  end

  r2rml do
    class_iri("https://example.org/ns#WidgetB")
    subject_template("https://example.org/ns-b/widgets/{id}")
    table_name("short_name_collision_ns_b_widgets")
    attribute_mappings([{:name, "https://example.org/ns#name"}])
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, public?: true, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, create: [:name], update: [:name]])
  end
end

defmodule AshR2RML.ShortNameCollision.Domain do
  @moduledoc "Domain containing both same-short-name resources, so any collision surfaces at schema build."
  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(AshR2RML.ShortNameCollision.NsA.Widget)
    resource(AshR2RML.ShortNameCollision.NsB.Widget)
  end
end

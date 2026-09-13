# SPDX-FileCopyrightText: 2026 ash_r2rml contributors <https://github.com/seanchatmangpt/ash_r2rml/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshR2RML.Adversarial.DatatypeClosureTest do
  @moduledoc """
  Hostile Adversarial Datatype Closure Test Suite.

  Exercises:
  1. Built-in scalar types: integer, decimal, boolean, utc_datetime, utc_datetime_usec, naive_datetime, uuid, string.
  2. Built-in timestamps (create_timestamp, update_timestamp).
  3. Enum types (Ash.Type.Enum modules and constrained atoms).
  4. Custom Ash.Type implementing AshR2RML.Type behaviour.
  5. Typed refusal on unmapped custom types (UNSUPPORTED_ASH_TYPE).
  6. Proof of law: Unknown Ash types NEVER silently fall back to xsd:string.
  7. Nullable & non-nullable attribute mapping validation.
  8. Preservation of Ash calculations, aggregates, and default attribute values.
  """
  use ExUnit.Case, async: true

  alias AshR2RML.Datatype.Registry
  alias AshR2RML.Refusal

  # 1. Custom Enum Module
  defmodule PublicationStatusEnum do
    use Ash.Type.Enum, values: [:draft, :in_review, :published, :archived]
  end

  # 2. Custom Ash scalar type implementing AshR2RML.Type
  defmodule MonetaryAmount do
    use Ash.Type

    use AshR2RML.Type,
      xsd_datatype: "https://example.org/ontology/MonetaryAmount"

    @impl Ash.Type
    def storage_type(_), do: :decimal

    @impl Ash.Type
    def cast_input(value, _constraints) when is_binary(value) do
      case Decimal.parse(value) do
        {decimal, ""} -> {:ok, decimal}
        _ -> {:error, "invalid monetary amount"}
      end
    end

    def cast_input(%Decimal{} = decimal, _constraints), do: {:ok, decimal}
    def cast_input(value, _constraints) when is_number(value), do: {:ok, Decimal.new("#{value}")}
    def cast_input(nil, _constraints), do: {:ok, nil}
    def cast_input(_, _constraints), do: {:error, "invalid monetary amount"}

    @impl Ash.Type
    def cast_stored(nil, _constraints), do: {:ok, nil}
    def cast_stored(val, _constraints), do: {:ok, Decimal.new("#{val}")}

    @impl Ash.Type
    def dump_to_native(nil, _constraints), do: {:ok, nil}
    def dump_to_native(%Decimal{} = decimal, _constraints), do: {:ok, decimal}
    def dump_to_native(val, _constraints), do: {:ok, Decimal.new("#{val}")}

    @impl AshR2RML.Type
    def to_rdf_lexical(%Decimal{} = decimal) do
      Decimal.to_string(decimal, :normal)
    end

    def to_rdf_lexical(val), do: to_string(val)
  end

  # 3. Unmapped custom struct / type without AshR2RML.Type
  defmodule UnmappedCustomType do
    use Ash.Type

    @impl Ash.Type
    def storage_type(_), do: :map

    @impl Ash.Type
    def cast_input(value, _constraints), do: {:ok, value}

    @impl Ash.Type
    def cast_stored(value, _constraints), do: {:ok, value}

    @impl Ash.Type
    def dump_to_native(value, _constraints), do: {:ok, value}
  end

  # 4. Comprehensive Admitted Resource with All Scalar Types, Enums, Timestamps, Calculations, Defaults
  defmodule ComprehensiveEntity do
    use Ash.Resource,
      domain: nil,
      data_layer: Ash.DataLayer.Ets,
      extensions: [AshR2RML.Resource]

    attributes do
      uuid_primary_key :id
      attribute :name, :string, allow_nil?: false, default: "Default Entity", public?: true
      attribute :view_count, :integer, allow_nil?: false, default: 0, public?: true
      attribute :price, :decimal, allow_nil?: false, public?: true
      attribute :is_active, :boolean, allow_nil?: false, default: true, public?: true
      attribute :published_at, :utc_datetime, allow_nil?: true, public?: true
      attribute :scheduled_at, :naive_datetime, allow_nil?: true, public?: true
      attribute :status, PublicationStatusEnum, allow_nil?: false, default: :draft, public?: true
      attribute :priority, :atom, constraints: [one_of: [:low, :medium, :high]], default: :low, public?: true
      attribute :budget, MonetaryAmount, allow_nil?: true, public?: true

      create_timestamp :inserted_at, public?: true
      update_timestamp :updated_at, public?: true
    end

    calculations do
      calculate :display_header, :string, expr(name <> " [" <> status <> "]")
    end

    actions do
      defaults [:read, :create, :update, :destroy]
    end

    r2rml do
      table_name("comprehensive_entities")
      class("https://example.org/ontology/ComprehensiveEntity")

      subject do
        template("https://example.org/entities/{id}")
      end

      property(:name, "http://xmlns.com/foaf/0.1/name")
      property(:view_count, "https://example.org/ontology/viewCount")
      property(:price, "https://example.org/ontology/price")
      property(:is_active, "https://example.org/ontology/isActive")
      property(:published_at, "https://example.org/ontology/publishedAt")
      property(:scheduled_at, "https://example.org/ontology/scheduledAt")
      property(:status, "https://example.org/ontology/status")
      property(:priority, "https://example.org/ontology/priority")
      property(:budget, "https://example.org/ontology/budget")
      property(:inserted_at, "http://purl.org/dc/terms/created")
      property(:updated_at, "http://purl.org/dc/terms/modified")
    end
  end

  describe "1. Built-in and Custom Datatype Resolution in Registry" do
    test "resolves all standard scalar Ash types to appropriate XSD datatype IRIs" do
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#integer"}} = Registry.resolve(:integer)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#decimal"}} = Registry.resolve(:decimal)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#boolean"}} = Registry.resolve(:boolean)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#dateTime"}} = Registry.resolve(:utc_datetime)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#dateTime"}} = Registry.resolve(:utc_datetime_usec)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#dateTime"}} = Registry.resolve(:naive_datetime)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"}} = Registry.resolve(:uuid)
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#string"}} = Registry.resolve(:string)
    end

    test "resolves :duration (Ash.Type.Duration, Ash >= 3.23) to xsd:duration" do
      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#duration", storage_type: :duration}} =
               Registry.resolve(:duration)

      assert {:ok, %{rdf_datatype: "http://www.w3.org/2001/XMLSchema#duration"}} =
               Registry.resolve(Ash.Type.Duration)
    end

    test "resolves Ash.Type.Enum modules to xsd:string without loss" do
      assert {:ok, dt} = Registry.resolve(PublicationStatusEnum)
      assert dt.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert Registry.supported?(PublicationStatusEnum) == true
    end

    test "resolves custom Ash.Type implementing AshR2RML.Type behaviour" do
      assert {:ok, dt} = Registry.resolve(MonetaryAmount)
      assert dt.rdf_datatype == "https://example.org/ontology/MonetaryAmount"
      assert Registry.supported?(MonetaryAmount) == true
    end
  end

  describe "2. Anti-Fallthrough Law: Unknown Types Never Silently Stringify" do
    test "refuses unmapped custom Ash.Type with typed refusal UNSUPPORTED_ASH_TYPE" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE} = refusal} = Registry.resolve(UnmappedCustomType)
      assert refusal.detail =~ "Ash type has no admitted RDF datatype contract"
      assert Registry.supported?(UnmappedCustomType) == false
    end

    test "refuses arbitrary unknown atoms or maps with UNSUPPORTED_ASH_TYPE" do
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:unknown_arbitrary_type)
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:map)
      assert {:error, %Refusal{code: :UNSUPPORTED_ASH_TYPE}} = Registry.resolve(:tuple)
    end

    test "refuses non-absolute RDF datatype overrides with REFUSED_UNMAPPED_DATATYPE" do
      assert {:error, %Refusal{code: :REFUSED_UNMAPPED_DATATYPE}} =
               Registry.resolve(:string, "relative-invalid-datatype")
    end
  end

  describe "3. Comprehensive Resource R2RML Compilation and Rendering" do
    test "persists and normalizes all admitted datatypes, enums, timestamps, and custom types into mapping IR" do
      mapping = AshR2RML.Resource.Info.mapping!(ComprehensiveEntity)

      # Verify all properties exist in normalized IR
      prop_map = Map.new(mapping.predicate_object_maps, &{&1.attribute, &1})

      assert prop_map[:name].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert prop_map[:view_count].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#integer"
      assert prop_map[:price].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#decimal"
      assert prop_map[:is_active].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#boolean"
      assert prop_map[:published_at].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#dateTime"
      assert prop_map[:scheduled_at].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#dateTime"
      assert prop_map[:status].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert prop_map[:priority].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#string"
      assert prop_map[:budget].object_map.datatype.rdf_datatype == "https://example.org/ontology/MonetaryAmount"
      assert prop_map[:inserted_at].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#dateTime"
      assert prop_map[:updated_at].object_map.datatype.rdf_datatype == "http://www.w3.org/2001/XMLSchema#dateTime"
    end

    test "renders standards-valid R2RML Turtle with exact datatype annotations" do
      assert {:ok, ttl} = AshR2RML.render(ComprehensiveEntity)

      assert ttl =~ "rr:predicate <http://xmlns.com/foaf/0.1/name>"
      assert ttl =~ "rr:datatype <http://www.w3.org/2001/XMLSchema#string>"
      assert ttl =~ "rr:predicate <https://example.org/ontology/viewCount>"
      assert ttl =~ "rr:datatype <http://www.w3.org/2001/XMLSchema#integer>"
      assert ttl =~ "rr:predicate <https://example.org/ontology/price>"
      assert ttl =~ "rr:datatype <http://www.w3.org/2001/XMLSchema#decimal>"
      assert ttl =~ "rr:predicate <https://example.org/ontology/isActive>"
      assert ttl =~ "rr:datatype <http://www.w3.org/2001/XMLSchema#boolean>"
      assert ttl =~ "rr:predicate <https://example.org/ontology/publishedAt>"
      assert ttl =~ "rr:datatype <http://www.w3.org/2001/XMLSchema#dateTime>"
      assert ttl =~ "rr:predicate <https://example.org/ontology/budget>"
      assert ttl =~ "rr:datatype <https://example.org/ontology/MonetaryAmount>"
      assert ttl =~ "rr:predicate <http://purl.org/dc/terms/created>"
      assert ttl =~ "rr:predicate <http://purl.org/dc/terms/modified>"
    end

    test "renders SHACL shapes graph preserving nullable vs non-nullable and datatypes" do
      assert {:ok, shacl} = AshR2RML.render_shacl([ComprehensiveEntity])

      assert shacl =~ "sh:NodeShape"
      assert shacl =~ "sh:targetClass <https://example.org/ontology/ComprehensiveEntity>"
      assert shacl =~ "sh:path <http://xmlns.com/foaf/0.1/name>"
      assert shacl =~ "sh:minCount 1"
      assert shacl =~ "sh:datatype <http://www.w3.org/2001/XMLSchema#string>"
    end

    test "preserves Ash calculation and default semantics on resource without interfering with R2RML" do
      # Ash calculation is accessible via Ash.Resource.Info
      calculations = Ash.Resource.Info.calculations(ComprehensiveEntity)
      assert Enum.any?(calculations, &(&1.name == :display_header))

      # Ash defaults are preserved on attributes
      name_attr = Ash.Resource.Info.attribute(ComprehensiveEntity, :name)
      assert name_attr.default == "Default Entity"
      assert name_attr.allow_nil? == false

      budget_attr = Ash.Resource.Info.attribute(ComprehensiveEntity, :budget)
      assert budget_attr.allow_nil? == true
    end
  end
end

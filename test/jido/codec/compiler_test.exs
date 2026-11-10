defmodule Jido.Codec.CompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Test.Codec.Fixtures.{Address, NamedMap, Person}

  test "compiles nested struct decoding from one Joi schema" do
    input = %{
      "name" => " Ada ",
      "address" => %{"street" => "Main", "postalCode" => "60601"},
      "state" => "active",
      "nickname" => nil,
      "tag" => "math"
    }

    assert {:ok,
            %Person{
              name: "Ada",
              address: %Address{street: "Main", postal_code: "60601"},
              state: :active,
              nickname: nil,
              tag: "math"
            }} = Person.from_map(input)
  end

  test "decodes with Elixir JSON" do
    json =
      ~s({"name":"Ada","address":{"street":"Main","postalCode":"60601"},"state":"disabled","tag":"math"})

    assert {:ok, %Person{state: :disabled, nickname: nil}} = Person.decode(json)
    assert %Person{state: :disabled} = Person.decode!(json)
  end

  test "dumps aliases and atom enums without keeping omitted nil fields" do
    person = %Person{
      name: "Ada",
      address: %Address{street: "Main", postal_code: "60601"},
      state: :active,
      nickname: nil,
      tag: "math"
    }

    assert Person.dump(person) == %{
             "name" => "ada",
             "address" => %{"street" => "Main", "postalCode" => "60601"},
             "state" => "active",
             "tag" => "math"
           }

    assert JSON.decode!(JSON.encode!(person)) == Person.dump(person)
  end

  test "compiles named map codecs" do
    assert {:ok, %{state: :ready, count: 2}} =
             NamedMap.from_map(%{"state" => "ready", "count" => 2})

    assert NamedMap.dump(%{state: :stopped, count: 3}) == %{
             "state" => "stopped",
             "count" => 3
           }
  end

  test "uses the Joi unknown-field and validation errors" do
    assert {:error, [%Zoi.Error{code: :unrecognized_key, path: ["extra"]}]} =
             NamedMap.from_map(%{"state" => "ready", "count" => 2, "extra" => true})

    assert {:error, [%Zoi.Error{} | _rest]} =
             NamedMap.from_map(%{"state" => "unknown", "count" => 2})
  end

  test "compiles the JSON Schema from Joi" do
    assert get_in(Person.json_schema(), [:properties, :state, :enum]) == [:active, :disabled]
  end

  test "the JSON Schema describes the wire shape" do
    schema = Person.json_schema()
    address = schema.properties.address

    assert %{"postalCode" => %{type: :string}} = address.properties
    refute Map.has_key?(address.properties, :postal_code)
    assert "postalCode" in address.required
    refute :postal_code in address.required

    assert Map.has_key?(schema.properties, :nickname)
    refute :nickname in schema.required

    for name <- [:name, :address, :state, :tag], do: assert(name in schema.required)
  end

  defmodule WireNames do
    alias Jido.Joi

    @schema Joi.object(%{
              first_name: Joi.string(),
              leaves: Joi.array(Address.schema()),
              maybe: Joi.nullable(Address.schema()),
              rows: Joi.array(Joi.object(%{cell: Joi.string()})),
              region: Joi.string() |> Joi.default("us")
            })
    use Jido.Codec, schema: @schema
    codec(:first_name, as: "firstName")
  end

  test "the JSON Schema applies wire names inside arrays and unions" do
    schema = WireNames.json_schema()

    assert %{required: required, properties: %{"firstName" => %{type: :string}} = properties} =
             schema

    assert "firstName" in required
    assert Map.has_key?(properties, :region)
    refute :region in required
    assert %{"postalCode" => _} = properties.leaves.items.properties
    assert [%{type: :null}, %{properties: %{"postalCode" => _}}] = properties.maybe.anyOf
    assert %{cell: _} = properties.rows.items.properties
  end
end

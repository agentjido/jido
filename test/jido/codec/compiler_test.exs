defmodule Jido.Codec.CompilerTest do
  use ExUnit.Case, async: true

  alias Jido.Test.CodecFixtures.{Address, NamedMap, Person}

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
    assert Person.json_schema() == Jido.Joi.to_json_schema(Person.schema())
    assert get_in(Person.json_schema(), [:properties, :state, :enum]) == [:active, :disabled]
  end
end

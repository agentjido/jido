Code.require_file("support/fuzz.exs", __DIR__)

defmodule JidoTest.Property.Signal.CatalogBoundariesTest do
  use ExUnit.Case, async: true
  import StreamData

  alias Jido.Error.ValidationError
  alias Jido.Signal.Catalog
  alias Jido.Signal.Codec
  alias JidoTest.Property.Signal.Fuzz

  defmodule MessageV1 do
    use Jido.Signal,
      type: "catalog.message",
      dataschema: "urn:catalog:message:1",
      schema: Zoi.object(%{"text" => Zoi.string()}, unrecognized_keys: :error)
  end

  defmodule MessageV2 do
    use Jido.Signal,
      type: "catalog.message",
      dataschema: "urn:catalog:message:2",
      schema:
        Zoi.object(%{"text" => Zoi.string(), "revision" => Zoi.integer()},
          unrecognized_keys: :error
        )
  end

  defmodule Sensor do
    use Jido.Signal,
      type: "catalog.sensor",
      schema: Zoi.object(%{"reading" => Zoi.integer()}, unrecognized_keys: :error)
  end

  @families ~w(message sensor unknown)
  @versions ~w(none v1 v2 unknown)
  @times [nil, "2026-10-12T01:02:03Z", "2026-10-12t01:02:03.1234567z"]

  for {suite, runs, bound} <- [{:property, 40, 16}, {:fuzz, 500, 128}] do
    @tag [
      {suite, true},
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    @tag contracts: ["CAT-001"]
    @tag contract_cases: [
           "CAT-001/exact-pairs",
           "CAT-001/preserved-identity",
           "CAT-001/data-errors",
           "CAT-001/constructor-identity"
         ]
    test "#{suite}: exact catalog selection and preserved identity", context do
      generator =
        fixed_map(%{
          "family" => member_of(@families),
          "version" => member_of(@versions),
          "n" => integer(-1_000_000..1_000_000),
          "text" => string(:alphanumeric, max_length: unquote(bound)),
          "time" => member_of(@times)
        })

      examples =
        for family <- @families,
            version <- @versions,
            time <- @times,
            do: %{
              "family" => family,
              "version" => version,
              "n" => 0,
              "text" => "é",
              "time" => time
            }

      Fuzz.check(
        "catalog_boundaries",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{
         "family" => family,
         "version" => version,
         "n" => n,
         "text" => text,
         "time" => time
       }) do
    definitions =
      if rem(n, 2) == 0, do: [MessageV1, MessageV2, Sensor], else: [Sensor, MessageV2, MessageV1]

    catalog = Catalog.new!(definitions)
    type = "catalog." <> family

    schema =
      case version do
        "none" -> nil
        "v1" -> "urn:catalog:message:1"
        "v2" -> "urn:catalog:message:2"
        "unknown" -> "urn:catalog:unknown"
      end

    data =
      case {family, version} do
        {"sensor", _} -> %{"reading" => n}
        {"message", "v2"} -> %{"text" => text, "revision" => n}
        _ -> %{"text" => text}
      end

    wire = %{
      "specversion" => "1.0",
      "id" => "fact-#{n}",
      "source" => "/source/#{n}",
      "type" => type,
      "dataschema" => schema,
      "data" => data,
      "time" => time,
      "subject" => "record/#{n}",
      "tenant" => n
    }

    # This table is independent of catalog metadata and lookup implementation.
    expected =
      case {family, version} do
        {"message", "v1"} -> {:ok, MessageV1}
        {"message", "v2"} -> {:ok, MessageV2}
        {"sensor", "none"} -> {:ok, Sensor}
        {"unknown", _} -> {:error, :unknown_type}
        _ -> {:error, :unknown_dataschema}
      end

    assert {:ok, generic} = Codec.from_map(wire)

    case expected do
      {:ok, definition} ->
        assert {:ok, ^generic} = Catalog.decode(catalog, wire)
        assert {:ok, ^generic} = Catalog.decode(catalog, Jason.encode!(wire))
        assert {:ok, ^generic} = Catalog.validate(catalog, generic)

        canonical =
          Map.reject(wire, fn {key, value} -> key in ["time", "dataschema"] and is_nil(value) end)

        assert Codec.to_map(generic) == canonical
        assert {:ok, encoded} = Codec.serialize(generic)
        assert Jason.decode!(encoded) == canonical

        assert {:ok, ^generic} =
                 Catalog.decode(catalog, encoded, max_payload_bytes: byte_size(encoded))

        opts =
          canonical
          |> Map.drop(["type", "data", "dataschema"])
          |> Map.merge(%{"type" => "wrong.type", "dataschema" => "urn:wrong", "data" => false})

        assert {:ok, ^generic} = definition.new(data, opts)

        bad = Map.put(wire, "data", false)
        assert_code(Catalog.decode(catalog, bad), :invalid_data)
        assert_code(Catalog.decode(catalog, Jason.encode!(bad)), :invalid_data)
        assert_code(Catalog.validate(catalog, %{generic | data: false}), :invalid_data)
        ["known_pair", "preserved_identity", "constructor_identity", "invalid_data"]

      {:error, code} ->
        assert_code(Catalog.decode(catalog, wire), code)
        assert_code(Catalog.decode(catalog, Jason.encode!(wire)), code)
        assert_code(Catalog.validate(catalog, generic), code)
        [Atom.to_string(code)]
    end
  end

  defp assert_code(result, code) do
    assert {:error, %ValidationError{details: %{code: ^code}}} = result
  end
end

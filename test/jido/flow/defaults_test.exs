defmodule Jido.Flow.DefaultsTest do
  use ExUnit.Case, async: true

  defmodule ConfiguredFlow do
    use Jido.Flow,
      name: "configured_flow",
      schema:
        Jido.Joi.object(
          %{
            input: Jido.Joi.string(),
            mode: Jido.Joi.enum([:fast, :safe]),
            modes: Jido.Joi.list(Jido.Joi.enum([:fast, :safe])),
            retries: Jido.Joi.integer(gte: 0, lte: 3),
            nested:
              Jido.Joi.object(
                %{
                  enabled: Jido.Joi.boolean(),
                  mode: Jido.Joi.enum([:fast, :safe]) |> Jido.Joi.optional()
                },
                unrecognized_keys: :error
              )
          },
          unrecognized_keys: :error
        )

    flow do
      step "done", input <- input(:input) do
        {:ok, %{input: input}}
      end

      output result("done")
    end
  end

  defmodule OpenFlow do
    use Jido.Flow, name: "open_flow", schema: Jido.Joi.map()

    flow do
      step "done", params <- input() do
        {:ok, params}
      end

      output result("done")
    end
  end

  test "normalizes partial defaults with the selected Flow schema" do
    assert {:ok, %{retries: 2, nested: %{enabled: true}}} =
             Jido.Flow.normalize_defaults(
               %{"retries" => 2, "nested" => %{"enabled" => true}},
               ConfiguredFlow
             )

    assert {:ok, %{label: "open"}} =
             Jido.Flow.normalize_defaults(%{label: "open"}, OpenFlow)
  end

  test "encodes and decodes defaults through the same Flow schema" do
    defaults = %{
      mode: :safe,
      modes: [:fast, :safe],
      retries: 2,
      nested: %{enabled: true, mode: :fast}
    }

    assert {:ok,
            %{
              "mode" => "safe",
              "modes" => ["fast", "safe"],
              "retries" => 2,
              "nested" => %{"enabled" => true, "mode" => "fast"}
            } = encoded} =
             Jido.Flow.encode_defaults(defaults, ConfiguredFlow)

    assert {:ok, ^defaults} = Jido.Flow.decode_defaults(encoded, ConfiguredFlow)
  end

  test "returns the exact invalid default path" do
    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{details: %{path: [:nested, :enabled]}}} =
             Jido.Flow.normalize_defaults(%{nested: %{enabled: "not-boolean"}}, ConfiguredFlow)

    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{details: %{path: ["unknown"]}}} =
             Jido.Flow.normalize_defaults(%{"unknown" => true}, ConfiguredFlow)
  end

  test "rejects non-portable defaults after schema validation" do
    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{details: %{path: [:value]}}} =
             Jido.Flow.normalize_defaults(%{value: self()}, OpenFlow)
  end

  test "rejects open defaults with duplicate JSON field names" do
    assert {:error,
            %Jido.Flow.Error.InvalidDefinitionError{
              details: %{code: :duplicate_field, path: ["mode"]}
            }} = Jido.Flow.encode_defaults(%{:mode => :safe, "mode" => "fast"}, OpenFlow)
  end

  test "rejects invalid subjects and non-object schemas" do
    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
             Jido.Flow.normalize_defaults([], ConfiguredFlow)

    assert {:error, %Jido.Flow.Error.InvalidDefinitionError{}} =
             Jido.Flow.normalize_defaults(%{}, String)
  end
end

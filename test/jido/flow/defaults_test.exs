defmodule Jido.Flow.DefaultsTest do
  use Covenant.Case, component: "jido_action.flow", async: true
  @moduletag obligation: "jido_action.flow.I12"

  defmodule ConfiguredFlow do
    use Jido.Flow,
      name: "configured_flow",
      schema:
        Jido.Joi.object(
          %{
            input: Jido.Joi.string(),
            ambiguous: Jido.Joi.union([Jido.Joi.any(), Jido.Joi.enum([:safe])]),
            mode: Jido.Joi.enum([:fast, :safe]),
            modes: Jido.Joi.list(Jido.Joi.enum([:fast, :safe])),
            mode_or_modes:
              Jido.Joi.union([
                Jido.Joi.enum([:fast, :safe]),
                Jido.Joi.list(Jido.Joi.enum([:fast, :safe])),
                Jido.Joi.list(Jido.Joi.list(Jido.Joi.enum([:fast, :safe])))
              ]),
            retries: Jido.Joi.integer(gte: 0, lte: 3),
            nested:
              Jido.Joi.object(
                %{
                  enabled: Jido.Joi.boolean(),
                  mode: Jido.Joi.enum([:fast, :safe]) |> Jido.Joi.optional(),
                  modes: Jido.Joi.list(Jido.Joi.enum([:fast, :safe])) |> Jido.Joi.optional()
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
    assert {:error, %Jido.Error.ValidationError{details: %{path: [:nested, :enabled]}}} =
             Jido.Flow.normalize_defaults(%{nested: %{enabled: "not-boolean"}}, ConfiguredFlow)

    assert {:error, %Jido.Error.ValidationError{details: %{path: ["unknown"]}}} =
             Jido.Flow.normalize_defaults(%{"unknown" => true}, ConfiguredFlow)
  end

  test "refuses a default that would change type after loading" do
    for input <- ["safe", :safe] do
      assert Jido.Flow.normalize_defaults(%{ambiguous: input}, ConfiguredFlow) ==
               {:ok, %{ambiguous: input}}
    end

    assert {:error, %Jido.Error.ValidationError{details: %{path: [:ambiguous]}}} =
             Jido.Flow.encode_defaults(%{ambiguous: "safe"}, ConfiguredFlow)

    assert {:ok, %{"ambiguous" => "safe"} = document} =
             Jido.Flow.encode_defaults(%{ambiguous: :safe}, ConfiguredFlow)

    assert {:ok, %{ambiguous: :safe}} = Jido.Flow.decode_defaults(document, ConfiguredFlow)
  end

  test "decoding improper arrays returns structured validation errors" do
    for {defaults, path} <- [
          {%{modes: ["safe" | :tail]}, [:modes]},
          {%{nested: %{enabled: true, modes: ["safe" | :tail]}}, [:nested]},
          {%{mode_or_modes: ["safe" | :tail]}, [:mode_or_modes]},
          {%{mode_or_modes: [["safe"], ["safe" | :tail]]}, [:mode_or_modes]}
        ] do
      assert {:error, %Jido.Error.ValidationError{details: %{path: ^path}}} =
               Jido.Flow.decode_defaults(defaults, ConfiguredFlow)
    end

    assert {:ok, %{mode_or_modes: [:safe]}} =
             Jido.Flow.decode_defaults(%{"mode_or_modes" => ["safe"]}, ConfiguredFlow)

    assert {:ok, %{mode_or_modes: [[:safe]]}} =
             Jido.Flow.decode_defaults(%{"mode_or_modes" => [["safe"]]}, ConfiguredFlow)
  end

  test "rejects non-portable defaults after schema validation" do
    assert {:error, %Jido.Error.ValidationError{details: %{path: [:value]}}} =
             Jido.Flow.normalize_defaults(%{value: self()}, OpenFlow)
  end

  test "rejects an open field whose atom key would change on load" do
    assert {:error, %{details: %{code: :ambiguous_default, path: ["config", :debug]}}} =
             Jido.Flow.encode_defaults(%{"config" => %{debug: true}}, OpenFlow)
  end

  test "rejects open defaults with duplicate JSON field names" do
    assert {:error,
            %Jido.Error.ValidationError{
              details: %{code: :duplicate_field, path: ["mode"]}
            }} = Jido.Flow.encode_defaults(%{:mode => :safe, "mode" => "fast"}, OpenFlow)
  end

  test "rejects invalid subjects and non-object schemas" do
    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Flow.normalize_defaults([], ConfiguredFlow)

    assert {:error, %Jido.Error.ValidationError{}} =
             Jido.Flow.normalize_defaults(%{}, String)
  end
end

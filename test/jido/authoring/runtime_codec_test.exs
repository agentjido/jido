defmodule Jido.Authoring.RuntimeCodecTest do
  use ExUnit.Case, async: false

  alias Jido.Authoring.Issue
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action, id: "tests/actions/runtime-echo", name: "runtime_echo"
    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule CrashingCodec do
    def __jido_authoring_codec__, do: %{type: "tests.crashing", vsn: 1}
    def decode_document(_document, _registry), do: throw(:codec_bug)
  end

  defmodule InvalidSuccessCodec do
    def __jido_authoring_codec__, do: %{type: "tests.invalid-success", vsn: 1}
    def decode_document(_document, _registry), do: {:ok, %{not: :a_struct}}
  end

  defmodule IssueCodec do
    def __jido_authoring_codec__, do: %{type: "tests.issue", vsn: 1}

    def decode_document(_document, _registry),
      do: {:error, [Issue.new(:codec_issue, ["field"], "codec issue")]}
  end

  defmodule Captured do
    defstruct [:value]
  end

  defmodule CaptureCodec do
    def __jido_authoring_codec__, do: %{type: "tests.capture", vsn: 1}

    def decode_document(%{"value" => value}, _registry),
      do: {:ok, %Captured{value: value}}
  end

  defmodule MetadataCrashCodec do
    def __jido_authoring_codec__, do: raise("metadata bug")
    def decode_document(_document, _registry), do: {:ok, %URI{}}
    def encode_document(_value, _registry), do: {:ok, %{}}
  end

  setup do
    {:ok, manifests} =
      Jido.Authoring.Manifest.validate(Echo, Echo.__jido_authoring__())

    codecs =
      [CaptureCodec, CrashingCodec, InvalidSuccessCodec, IssueCodec, Jido.Flow.Codec]
      |> Enum.map(fn module ->
        {:ok, metadata} = Jido.Authoring.Codec.metadata(module)
        Map.put(metadata, :module, module)
      end)

    {:ok, registry} = Jido.Authoring.Registry.new_discovered(manifests, codecs)
    %{registry: registry}
  end

  test "encodes and decodes a Flow", %{registry: registry} do
    flow = flow()
    assert {:ok, document} = Jido.Authoring.encode(flow, registry: registry)
    refute Map.has_key?(document, "vsn")
    assert {:ok, json} = Jido.Authoring.encode_json(flow, registry: registry)
    assert Jason.decode!(json) == document

    assert {:ok, ^flow} = Jido.Authoring.decode_json(json, registry: registry)
  end

  test "rejects unsupported encode values", %{registry: registry} do
    assert {:error, %Jido.Authoring.Error.InvalidError{code: :unsupported_value}} =
             Jido.Authoring.encode(:unsupported, registry: registry)
  end

  test "applies the JSON byte limit", %{registry: registry} do
    {:ok, document} = Jido.Authoring.encode(flow(), registry: registry)
    size = document |> Jason.encode!() |> byte_size()

    assert {:ok, ^document} =
             Jido.Authoring.encode(flow(), registry: registry, maximum_json_bytes: size)

    assert {:error, %Jido.Authoring.Error.InvalidError{code: :document_too_large}} =
             Jido.Authoring.encode(flow(),
               registry: registry,
               maximum_json_bytes: size - 1
             )

    assert {:error, [%Issue{code: :bytes}]} =
             Jido.Authoring.decode(document,
               registry: registry,
               maximum_json_bytes: size - 1
             )
  end

  test "rejects a version on an unversioned Flow document", %{registry: registry} do
    {:ok, document} = Jido.Authoring.encode(flow(), registry: registry)

    assert {:error, [%Issue{code: :unsupported_document, path: ["type"]}]} =
             Jido.Authoring.decode(Map.put(document, "vsn", 1), registry: registry)
  end

  test "contains codec failures and invalid returns", %{registry: registry} do
    assert {:error,
            [
              %Issue{
                code: :codec_failure,
                details: %{failure_kind: :throw, reason: ":codec_bug"}
              }
            ]} =
             Jido.Authoring.decode(
               %{"type" => "tests.crashing", "vsn" => 1},
               registry: registry
             )

    assert {:error, [%Issue{code: :invalid_codec_return}]} =
             Jido.Authoring.decode(
               %{"type" => "tests.invalid-success", "vsn" => 1},
               registry: registry
             )
  end

  test "contains explicit codec metadata failures", %{registry: registry} do
    assert {:error,
            [
              %Issue{
                code: :codec_failure,
                details: %{failure_kind: :error, reason: "metadata bug"}
              }
            ]} =
             Jido.Authoring.decode(
               %{"type" => "tests.crashing-metadata", "vsn" => 1},
               registry: registry,
               codec: MetadataCrashCodec
             )

    assert {:error, %Jido.Authoring.Error.InternalError{code: :codec_failure}} =
             Jido.Authoring.encode(flow(), registry: registry, codec: MetadataCrashCodec)
  end

  test "preserves ordered issues returned by a codec", %{registry: registry} do
    assert {:error, [%Issue{code: :codec_issue, path: ["field"]}]} =
             Jido.Authoring.decode(
               %{"type" => "tests.issue", "vsn" => 1},
               registry: registry
             )
  end

  test "copies retained JSON strings", %{registry: registry} do
    value = String.duplicate("v", 128)

    json =
      Jason.encode!(%{
        "type" => "tests.capture",
        "vsn" => 1,
        "value" => value,
        "padding" => String.duplicate("x", 1_000_000)
      })

    assert {:ok, %Captured{value: decoded}} =
             Jido.Authoring.decode_json(json, registry: registry)

    assert decoded == value
    assert :binary.referenced_byte_size(decoded) == byte_size(decoded)
  end

  test "rejects duplicate JSON object keys", %{registry: registry} do
    json = ~s({"type":"tests.capture","vsn":1,"value":"first","value":"second"})

    assert {:error,
            [
              %Issue{
                code: :duplicate_key,
                path: ["value"],
                details: %{key: "value"}
              }
            ]} = Jido.Authoring.decode_json(json, registry: registry)
  end

  test "bounds ordered JSON conversion before codec dispatch", %{registry: registry} do
    deep_json =
      ~s({"type":"tests.capture","vsn":1,"value":) <>
        String.duplicate("[", 101) <> "null" <> String.duplicate("]", 101) <> "}"

    wide_json =
      Jason.encode!(%{
        "type" => "tests.capture",
        "vsn" => 1,
        "value" => List.duplicate(nil, 10_001)
      })

    many_nodes_json =
      Jason.encode!(%{
        "type" => "tests.capture",
        "vsn" => 1,
        "value" => List.duplicate(List.duplicate(nil, 10_000), 10)
      })

    for {json, code} <- [
          {deep_json, :depth},
          {wide_json, :collection},
          {many_nodes_json, :nodes}
        ] do
      assert {:error, [%Issue{code: ^code}]} =
               Jido.Authoring.decode_json(json, registry: registry)
    end
  end

  test "returns classified Splode errors" do
    invalid = Jido.Authoring.Error.invalid(:invalid_document, "invalid")
    internal = Jido.Authoring.Error.internal(:codec_failure, "failed")

    assert %Jido.Authoring.Error.InvalidError{class: :invalid} = invalid
    assert %Jido.Authoring.Error.InternalError{class: :internal} = internal
    assert Jido.Authoring.Error.splode_error?(invalid)
    assert Jido.Authoring.Error.splode_error?(internal)

    assert %Jido.Authoring.Error.Invalid{
             errors: [%Jido.Authoring.Error.InvalidError{code: :invalid_document}]
           } = Jido.Authoring.Error.to_class([invalid])
  end

  test "rejects malformed envelopes", %{registry: registry} do
    cases = [
      {fn -> Jido.Authoring.decode_json("{", registry: registry) end, :invalid_json},
      {fn -> Jido.Authoring.decode(%{"vsn" => 1}, registry: registry) end,
       :missing_document_type},
      {fn -> Jido.Authoring.decode([], registry: registry) end, :invalid_document},
      {fn ->
         Jido.Authoring.decode(%{"type" => "jido.flow", "vsn" => 0}, registry: registry)
       end, :invalid_document_vsn}
    ]

    for {validate, code} <- cases do
      assert {:error, [%Issue{code: ^code}]} = validate.()
    end
  end

  defp flow do
    Flow.new!(%{
      name: "runtime_json",
      forms: %{"echo" => {Echo, %{"message" => "hello"}}},
      output: Ref.result("echo")
    })
  end
end

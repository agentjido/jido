defmodule Jido.Codec.RuntimeCodecTest do
  use ExUnit.Case, async: false

  alias Jido.Codec.Issue
  alias Jido.Flow
  alias Jido.Flow.Ref

  defmodule Echo do
    use Jido.Action, id: "tests/actions/runtime-echo", name: "runtime_echo"
    @impl true
    def run(params, _context), do: {:ok, params}
  end

  defmodule CrashingCodec do
    @behaviour Jido.Codec.Contract
    def type, do: "tests.crashing"
    def version, do: 1
    def target, do: nil
    def decode(_document, _registry), do: throw(:codec_bug)
  end

  defmodule InvalidSuccessCodec do
    @behaviour Jido.Codec.Contract
    def type, do: "tests.invalid-success"
    def version, do: 1
    def target, do: nil
    def decode(_document, _registry), do: {:ok, %{not: :a_struct}}
  end

  defmodule IssueCodec do
    @behaviour Jido.Codec.Contract
    def type, do: "tests.issue"
    def version, do: 1
    def target, do: nil

    def decode(_document, _registry),
      do: {:error, [Issue.new(:codec_issue, ["field"], "codec issue")]}
  end

  defmodule Captured do
    defstruct [:value]
  end

  defmodule ExternalValue do
    defstruct [:value]
  end

  defmodule ExternalCodec do
    @behaviour Jido.Codec.Contract
    alias Jido.Codec.RuntimeCodecTest.ExternalValue

    def type, do: "tests.external"
    def version, do: 1
    def target, do: ExternalValue

    def encode(%ExternalValue{value: value}, _registry),
      do: {:ok, %{"type" => type(), "vsn" => version(), "value" => value}}

    def decode(%{"type" => "tests.external", "vsn" => 1, "value" => value}, _registry),
      do: {:ok, %ExternalValue{value: value}}
  end

  defmodule CaptureCodec do
    @behaviour Jido.Codec.Contract
    def type, do: "tests.capture"
    def version, do: 1
    def target, do: nil

    def decode(%{"value" => value}, _registry),
      do: {:ok, %Captured{value: value}}
  end

  defmodule MetadataCrashCodec do
    @behaviour Jido.Codec.Contract
    def type, do: raise("metadata bug")
    def version, do: 1
    def target, do: Jido.Flow
    def decode(_document, _registry), do: {:ok, %URI{}}
    def encode(_value, _registry), do: {:ok, %{}}
  end

  setup do
    previous = :persistent_term.get({:jido, :catalog_snapshot}, :not_initialized)

    on_exit(fn ->
      if previous == :not_initialized,
        do: :persistent_term.erase({:jido, :catalog_snapshot}),
        else: :persistent_term.put({:jido, :catalog_snapshot}, previous)
    end)

    :ok =
      Jido.Catalog.Discovery.refresh(
        applications: [],
        modules: [
          {CaptureCodec, :jido},
          {CrashingCodec, :jido},
          {ExternalCodec, :jido},
          {InvalidSuccessCodec, :jido},
          {IssueCodec, :jido},
          {Echo, :jido},
          {Jido.Flow.Codec, :jido}
        ]
      )

    %{registry: Jido.Catalog.Discovery.codec_index()}
  end

  test "uses Discovery only when routing needs the default Registry", %{registry: registry} do
    snapshot = :persistent_term.get({:jido, :catalog_snapshot})
    :persistent_term.erase({:jido, :catalog_snapshot})
    assert {:ok, _document} = Jido.Codec.encode(flow(), registry: registry)
    assert {:error, [%Issue{code: :invalid_json}]} = Jido.Codec.decode_json("{")
    assert {:error, [%Issue{code: :invalid_document}]} = Jido.Codec.decode([])

    assert_raise Jido.Codec.Error.InternalError, fn -> Jido.Codec.encode(flow()) end

    :persistent_term.put({:jido, :catalog_snapshot}, %{snapshot | registry: registry})
    assert {:ok, document} = Jido.Codec.encode(flow())
    assert {:ok, %Flow{}} = Jido.Codec.decode(document)
  end

  test "encodes and decodes a Flow", %{registry: registry} do
    flow = flow()
    assert {:ok, document} = Jido.Codec.encode(flow, registry: registry)
    assert {:ok, json} = Jido.Codec.encode_json(flow, registry: registry)
    assert Jason.decode!(json) == document

    assert {:ok, ^flow} = Jido.Codec.decode_json(json, registry: registry)
  end

  test "uses the Registry fallback for an external codec without a protocol implementation", %{
    registry: registry
  } do
    value = %ExternalValue{value: "runtime"}

    assert Jido.Codec.Encoder.codec(value) == :error
    assert {:ok, document} = Jido.Codec.encode(value, registry: registry)
    assert document == %{"type" => "tests.external", "vsn" => 1, "value" => "runtime"}
    assert {:ok, ^value} = Jido.Codec.decode(document, registry: registry)
  end

  test "rejects unsupported encode values", %{registry: registry} do
    assert {:error, %Jido.Codec.Error.InvalidError{code: :unsupported_value}} =
             Jido.Codec.encode(:unsupported, registry: registry)
  end

  test "applies the JSON byte limit", %{registry: registry} do
    {:ok, document} = Jido.Codec.encode(flow(), registry: registry)
    size = document |> Jason.encode!() |> byte_size()

    assert {:ok, ^document} =
             Jido.Codec.encode(flow(), registry: registry, maximum_json_bytes: size)

    assert {:error, %Jido.Codec.Error.InvalidError{code: :document_too_large}} =
             Jido.Codec.encode(flow(),
               registry: registry,
               maximum_json_bytes: size - 1
             )

    assert {:error, [%Issue{code: :bytes}]} =
             Jido.Codec.decode(document,
               registry: registry,
               maximum_json_bytes: size - 1
             )
  end

  test "reports a missing version without a repair system", %{registry: registry} do
    {:ok, document} = Jido.Codec.encode(flow(), registry: registry)

    assert {:error,
            [
              %Issue{
                code: :missing_document_vsn,
                path: ["vsn"],
                details: %{supported_vsns: [2]}
              }
            ]} = Jido.Codec.decode(Map.delete(document, "vsn"), registry: registry)
  end

  test "contains codec failures and invalid returns", %{registry: registry} do
    assert {:error,
            [
              %Issue{
                code: :codec_failure,
                details: %{failure_kind: :throw, reason: ":codec_bug"}
              }
            ]} =
             Jido.Codec.decode(
               %{"type" => "tests.crashing", "vsn" => 1},
               registry: registry
             )

    assert {:error, [%Issue{code: :invalid_codec_return}]} =
             Jido.Codec.decode(
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
             Jido.Codec.decode(
               %{"type" => "tests.crashing-metadata", "vsn" => 1},
               registry: registry,
               codec: MetadataCrashCodec
             )

    assert {:error, %Jido.Codec.Error.InternalError{code: :codec_failure}} =
             Jido.Codec.encode(flow(), registry: registry, codec: MetadataCrashCodec)
  end

  test "preserves ordered issues returned by a codec", %{registry: registry} do
    assert {:error, [%Issue{code: :codec_issue, path: ["field"]}]} =
             Jido.Codec.decode(
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
             Jido.Codec.decode_json(json, registry: registry)

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
            ]} = Jido.Codec.decode_json(json, registry: registry)
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
               Jido.Codec.decode_json(json, registry: registry)
    end
  end

  test "returns classified Splode errors" do
    invalid = Jido.Codec.Error.invalid(:invalid_document, "invalid")
    internal = Jido.Codec.Error.internal(:codec_failure, "failed")

    assert %Jido.Codec.Error.InvalidError{class: :invalid} = invalid
    assert %Jido.Codec.Error.InternalError{class: :internal} = internal
    assert Jido.Codec.Error.splode_error?(invalid)
    assert Jido.Codec.Error.splode_error?(internal)

    assert %Jido.Codec.Error.Invalid{
             errors: [%Jido.Codec.Error.InvalidError{code: :invalid_document}]
           } = Jido.Codec.Error.to_class([invalid])
  end

  test "rejects malformed envelopes", %{registry: registry} do
    cases = [
      {fn -> Jido.Codec.decode_json("{", registry: registry) end, :invalid_json},
      {fn -> Jido.Codec.decode(%{"vsn" => 1}, registry: registry) end, :missing_document_type},
      {fn -> Jido.Codec.decode([], registry: registry) end, :invalid_document},
      {fn ->
         Jido.Codec.decode(%{"type" => "jido.flow", "vsn" => 0}, registry: registry)
       end, :invalid_document_vsn}
    ]

    for {validate, code} <- cases do
      assert {:error, [%Issue{code: ^code}]} = validate.()
    end
  end

  defp flow do
    Flow.new!(%{
      name: "runtime_json",
      components: [%{name: "echo", kind: :step, action: Echo, params: %{"message" => "hello"}}],
      output: Ref.result("echo")
    })
  end
end

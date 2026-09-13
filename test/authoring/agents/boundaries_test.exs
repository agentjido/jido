Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoTest.Authoring.Agents.BoundariesTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.Agent
  alias Jido.Agent.{Builder, Codec}
  alias JidoTest.Authoring.Agents.Corpus

  setup do
    Corpus.load_dependencies!()
    :ok
  end

  for {file, message} <- [
        {"missing_source", "signal_source is required for define"},
        {"duplicate_schema", "Fields declared in both keyword and block form"},
        {"optional_list", "must use input options"},
        {"helper_collision", "Generated function conflicts with replace_signal/1"},
        {"plugin_conflict", "Plugin-owned Agent state key conflicts with the domain schema"}
      ] do
    @file_path "invalid/#{file}.exs"
    @message message
    test "invalid source: #{file}" do
      error = assert_raise CompileError, fn -> Corpus.compile_file(@file_path) end
      assert error.file == Corpus.fixture(@file_path)
      assert error.line > 0
      assert error.description =~ @message
    end
  end

  for variant <- [:counter_block, :inline, :flow_plugin] do
    @variant variant
    test "#{variant}: optional generated helper keeps omissions and fresh IDs" do
      Corpus.load!(@variant)
      spec = Corpus.spec(@variant)
      module = spec.attrs.module
      assert {:ok, first} = module.add_signal()
      assert {:ok, second} = module.add_signal()
      assert first.data == %{}
      assert first.source == spec.source
      assert first.type == elem(hd(spec.steps), 0)
      assert first.id != second.id
      assert {:ok, explicit} = module.add_signal(3)
      assert explicit.data == %{amount: 3}
    end
  end

  test "keyword authoring does not generate undeclared helpers" do
    Corpus.load!(:counter_keyword)
    module = Corpus.spec(:counter_keyword).attrs.module
    refute function_exported?(module, :add_signal, 0)
  end

  test "Builder branches are independent and retain their first error" do
    Corpus.load!(:counter_block)
    base = :counter_block |> Corpus.spec() |> Corpus.builder()
    original = Builder.build!(base)
    branch = Builder.name(base, "branched") |> Builder.build!()
    assert branch === %{original | name: "branched"}
    assert Builder.build!(base) === original
    invalid = Builder.name(base, 42)
    assert {:error, error} = Builder.build(invalid)
    assert {:error, ^error} = invalid |> Builder.name("fixed") |> Builder.build()
  end

  test "required state cannot be omitted and unknown state fields are rejected" do
    Corpus.load!(:required_profile)
    spec = Corpus.spec(:required_profile)

    for form <- Corpus.forms() do
      definition = Corpus.definition(spec, form)
      assert {:error, %Jido.Error.ValidationError{}} = Agent.instantiate(definition)

      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.instantiate(definition, state: %{name: "Ada", extra: true})
    end
  end

  test "state defaults treat nil as missing while nullable input remains explicit" do
    Corpus.load!(:falsy_values)
    spec = Corpus.spec(:falsy_values)

    for form <- Corpus.forms() do
      definition = Corpus.definition(spec, form)
      assert {:ok, instance} = Agent.instantiate(definition, state: %{enabled: nil, amount: nil})
      assert instance.state === %{enabled: false, amount: 0, note: nil}
    end
  end

  test "required list helper accepts empty lists and does not confuse them with options" do
    Corpus.load!(:list_inputs)
    spec = Corpus.spec(:list_inputs)
    module = spec.attrs.module

    for items <- [[], ["a", "b"]] do
      assert {:ok, signal} = module.replace_signal(items)
      assert signal.type == "items.replace"
      assert signal.source == spec.source
      assert signal.data === %{items: items}
      assert {:ok, %{state: %{items: ^items}}, []} = Agent.cmd(module.new!(), signal)
    end
  end

  test "lowered and built Flow targets support their named generated interfaces" do
    Corpus.load!(:extension_route)
    extension = Corpus.spec(:extension_route).attrs.module
    assert {:ok, text_signal} = extension.write_signal("after lowering")
    assert text_signal.data == %{text: "after lowering"}

    assert {:ok, %{state: %{text: "after lowering"}}, []} =
             Agent.cmd(extension.new!(), text_signal)

    Corpus.load!(:built_flow)
    built = Corpus.spec(:built_flow).attrs.module
    assert {:ok, value_signal} = built.set_signal(9)
    assert value_signal.data == %{value: 9}
    assert {:ok, %{state: %{total: 9}}, []} = Agent.cmd(built.new!(), value_signal)
  end

  test "reversing equal-priority routes changes the winner after JSON decoding" do
    Corpus.load!(:ordered_routes)
    spec = Corpus.spec(:ordered_routes)
    reversed = Map.update!(spec.document, "routes", &Enum.reverse/1)
    assert {:ok, definition} = Codec.decode(reversed, spec.registry)
    assert {:ok, ^reversed} = Codec.encode(definition, spec.registry)
    signal = Jido.Signal.new!("ordered.pick", %{}, source: spec.source)

    assert {:ok, %{state: %{selected: "second"}}, []} =
             Agent.cmd(Agent.instantiate!(definition), signal)
  end

  test "reversing Plugin order changes the state observed by the second reduction" do
    Corpus.load!(:ordered_plugins)
    spec = Corpus.spec(:ordered_plugins)
    reversed = Map.update!(spec.document, "plugins", &Enum.reverse/1)
    assert {:ok, definition} = Codec.decode(reversed, spec.registry)
    assert {:ok, ^reversed} = Codec.encode(definition, spec.registry)
    signal = Jido.Signal.new!("plugins.set", %{value: 2}, source: spec.source)

    assert {:ok, %{state: %{value: 2, first: 3, second: 0}}, []} =
             Agent.cmd(Agent.instantiate!(definition), signal)
  end

  for variant <- Corpus.variants() do
    @variant variant
    test "#{variant}: JSON rejects missing, mistyped, and untrusted references" do
      Corpus.load!(@variant)
      spec = Corpus.spec(@variant)

      for document <- [
            Map.delete(spec.document, "schema"),
            Map.put(spec.document, "version", 99),
            Map.put(spec.document, "module", "untrusted/agent"),
            Map.put(spec.document, "schema", spec.document["module"])
          ] do
        assert {:error, %Jido.Error.ValidationError{}} = Codec.decode(document, spec.registry)
      end
    end
  end
end

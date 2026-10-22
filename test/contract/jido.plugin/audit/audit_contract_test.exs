defmodule JidoTest.Contract.PluginAuditTest do
  use Covenant.Case, component: "jido.plugin.audit", async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Plugin.Reduction
  alias Jido.Plugin.Audit
  alias Jido.Plugin.Audit.Record
  alias Jido.Plugin.Normalizer

  defp reduction(plugin_state, directives) do
    %Reduction{
      plugin: Audit,
      agent_id: "audit-contract",
      agent_module: __MODULE__,
      signal: Jido.Signal.new!("audit.contract", %{}, source: "/contract"),
      state_before: %{audit: plugin_state},
      state: %{audit: plugin_state},
      plugin_state: plugin_state,
      prepared_input: nil,
      directives: directives
    }
  end

  @tag obligation: "jido.plugin.audit.I1"
  test "record construction preserves present options and generates absent values" do
    id = Jido.Signal.ID.generate!()

    assert Audit.record(:saved, :accepted,
             id: id,
             at: 0,
             metadata: %{source: :contract}
           ) == %Record{
             id: id,
             at: 0,
             event: :saved,
             outcome: :accepted,
             metadata: %{source: :contract}
           }

    assert %Record{id: nil, at: nil} =
             Audit.record(:saved, :accepted, id: nil, at: nil)

    before = System.system_time(:millisecond)
    generated = Audit.record({:saved, 1}, :accepted)
    after_time = System.system_time(:millisecond)

    assert Jido.Signal.ID.valid?(generated.id)
    assert generated.at in before..after_time
    assert generated.event == {:saved, 1}
    assert generated.outcome == :accepted
    assert generated.metadata == %{}

    for opts <- [
          [unknown: true],
          [id: id, id: id],
          %{id: id},
          [1],
          [{:id, id} | :invalid]
        ] do
      assert_raise ArgumentError, fn -> Audit.record(:saved, :accepted, opts) end
    end
  end

  @tag obligation: "jido.plugin.audit.I2"
  test "Record validation requires its declared value shapes" do
    record = Audit.record({:saved, 1}, :accepted, at: 0, metadata: %{source: :contract})
    assert %Zoi.Types.Struct{module: Record} = Record.schema()
    assert {:ok, ^record} = Record.validate(record)
    assert {:ok, ^record} = Directive.validate(record)

    invalid_id = %{record | id: "not-a-uuid7"}

    assert {:error, %Jido.Error.ValidationError{details: %{id: "not-a-uuid7"}}} =
             Record.validate(invalid_id)

    for invalid <- [nil, %{}] do
      assert {:error, %Jido.Error.ValidationError{details: %{expected: Record}}} =
               Record.validate(invalid)
    end

    for invalid <- [
          %{record | id: nil},
          %{record | at: -1},
          %{record | outcome: "accepted"},
          %{record | metadata: []}
        ] do
      assert {:error, _reason} = Record.validate(invalid)
    end
  end

  @tag obligation: "jido.plugin.audit.I2"
  test "Record validation rejects every non-portable record location" do
    for {record, path} <- [
          {Audit.record(<<5::3>>, :accepted), [:record, :event]},
          {Audit.record({:event, [<<5::3>>]}, :accepted), [:record, :event, 1, 0]},
          {Audit.record(:event, :accepted, metadata: %{nested: [%{bits: <<5::3>>}]}),
           [:record, :metadata, :nested, 0, :bits]},
          {Audit.record(:event, :accepted, metadata: %{<<5::3>> => :value}),
           [:record, :metadata, {:map_key, 0}]}
        ] do
      assert {:error, %Jido.Error.ValidationError{details: %{path: ^path}}} =
               Record.validate(record)
    end
  end

  @tag obligation: "jido.plugin.audit.I3"
  test "the Plugin declares one default field, one Directive, and a positive limit" do
    assert %{option_keys: %{agent: [:max_entries]}} = Audit.__jido_plugin__()
    assert {:audit, schema} = Audit.state_spec([])
    assert schema.meta.default == {:value, %{records: []}}
    assert {:ok, %{records: []}} = Jido.Schema.parse(schema, %{}, :initialize)
    assert Audit.directives([]) == [Record]
    assert {:audit, ^schema} = Audit.state_spec(max_entries: 1)

    for invalid <- [0, -1, nil, 1.0, :infinity] do
      assert_raise ArgumentError, ~r/Audit max_entries must be a positive integer/, fn ->
        Audit.state_spec(max_entries: invalid)
      end
    end

    assert {:ok, [_spec]} = Normalizer.normalize_all([{Audit, [max_entries: 1]}])

    for opts <- [[unknown: true], [max_entries: 1, max_entries: 2]] do
      assert {:error, _reason} = Normalizer.normalize_all([{Audit, opts}])
    end
  end

  @tag obligation: "jido.plugin.audit.I4"
  test "bounded updates retain the newest records in original order" do
    records = for i <- 1..7, do: Audit.record(i, :accepted, at: i)

    for existing <- [[], Enum.take(records, 2), Enum.take(records, 4)],
        incoming <- [[], Enum.drop(records, 4), records] do
      state = %{records: existing}
      expected = Enum.take(existing ++ incoming, -3)

      assert {:ok, %{records: ^expected}} =
               Audit.apply_records(state, incoming, max_entries: 3)
    end

    existing = Enum.take(records, 4)
    incoming = [Enum.at(records, 4)]

    assert {:ok, %{records: retained}} =
             Audit.apply_records(%{records: existing}, incoming, max_entries: 3)

    assert Enum.map(retained, & &1.event) == [3, 4, 5]

    oversized = %{records: for(i <- 1..1_001, do: Audit.record(i, :accepted, at: i))}
    assert {:ok, %{records: retained}} = Audit.apply_records(oversized, [], [])
    assert length(retained) == 1_000
    assert hd(retained).event == 2
    assert List.last(retained).event == 1_001
  end

  @tag obligation: "jido.plugin.audit.I4"
  test "reduction selects only Audit Records and applies the same bound" do
    first = Audit.record(:first, :accepted, at: 1)
    second = Audit.record(:second, :accepted, at: 2)
    unrelated = Directive.emit(Jido.Signal.new!("audit.other", %{}, source: "/contract"))
    input = reduction(%{records: []}, [first, unrelated, second])

    assert {:ok, %{records: [^first, ^second]}} = Audit.reduce(input, max_entries: 2)
    assert {:ok, %{records: [^second]}} = Audit.reduce(input, max_entries: 1)
  end
end

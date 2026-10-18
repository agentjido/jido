defmodule JidoTest.Contract.AgentExecutionTest do
  use Covenant.Case, component: "jido.agent", async: true
  alias Jido.Agent
  alias Jido.Agent.{Directive, Runner, Turn}
  alias JidoTest.AgentContract, as: F

  defp route(path, target, opts \\ []),
    do: Map.merge(%{path: path, handler: %{kind: :action, target: target}}, Map.new(opts))

  @tag obligation: ["jido.agent.I12", "jido.agent.I13"]
  test "the first declared matching route selects one target and merges defaults shallowly" do
    source =
      F.instance(
        routes: [
          route("test.run", F.Return, defaults: %{amount: 1, nested: %{a: 1, b: 2}}),
          route("test.*", F.Add)
        ]
      )

    signal = F.signal(%{amount: 7, nested: %{a: 9}})

    assert {:ok,
            %Turn{
              executable: F.Return,
              input: %{amount: 7, nested: %{a: 9}},
              source_signal: ^signal
            }} = Runner.prepare_default_turn(signal, source)

    assert {:ok, ^source, []} = Agent.cmd(source, signal, context: %{observer: self()})
    assert_receive {:executed, %{amount: 7, nested: %{a: 9}}, %{signal: ^signal}}
    assert {:error, _} = Agent.cmd(source, F.signal(%{mode: :error}))
    refute_received {:executed, _, _}
  end

  @tag obligation: "jido.agent.I14"
  test "map, duplicate keyword and nil input use the original source Signal" do
    source = F.instance(routes: [route("test.run", F.Return, defaults: %{amount: 3})])

    for {data, expected} <- [
          {%{}, %{amount: 3}},
          {nil, %{amount: 3}},
          {[amount: 1, amount: 0], %{amount: 0}},
          {%{amount: false}, %{amount: false}}
        ] do
      signal = F.signal(data)
      assert {:ok, ^source, []} = Agent.cmd(source, signal, context: %{observer: self()})
      assert_receive {:executed, ^expected, %{signal: ^signal}}
    end

    for data <- [:invalid, "bad", [1, 2], [1 | :tail]] do
      assert {:error, _} = Agent.cmd(source, F.signal(data), context: %{observer: self()})
    end

    refute_received {:executed, _, _}
  end

  @tag obligation: "jido.agent.I15"
  test "reserved context fails and valid caller context and execution options are retained" do
    source = F.instance()

    for key <- [:agent_id, :agent_state, :agent_topology, :plugin_inputs, :signal] do
      assert {:error, _} = Agent.cmd(source, F.signal(), context: %{key => :forged})
    end

    signal = F.signal()

    assert {:ok, ^source, []} =
             Agent.cmd(source, signal,
               context: %{observer: self(), request: 2},
               timeout: 1000,
               max_attempts: 2,
               backoff: :none
             )

    assert_receive {:executed, %{}, %{request: 2, signal: ^signal, agent_state: state}}
    assert state === source.state

    for options <- [[timeout: -1], [max_attempts: 0], [backoff: :invalid]] do
      assert {:error, %Jido.Action.Error.ConfigurationError{}} =
               Agent.cmd(source, signal, options)
    end
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I16", "jido.agent.I17"]
  test "success requires complete valid state and failure preserves the next command" do
    source = F.instance()

    for output <- [
          Map.delete(source.state, :count),
          %{source.state | count: "1"},
          Map.put(source.state, :extra, 1),
          [],
          nil,
          %URI{}
        ] do
      assert {:error, _} = Agent.cmd(source, F.signal(%{output: output}))
    end

    assert {:error, _} = Agent.cmd(source, F.signal(%{mode: :error}))
    output = %{source.state | count: 3, enabled: false, note: nil}
    assert {:ok, candidate, []} = Agent.cmd(source, F.signal(%{output: output}))
    assert candidate === %{source | state: output}
    assert Agent.definition(candidate) === Agent.definition(source)
    assert source.state.count == 0
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I19"]
  test "the complete directive batch validates in order without dispatch" do
    source = F.instance()

    effects =
      Enum.map(
        ["first", "second"],
        &Directive.emit(F.signal(%{}, "effect." <> &1), {:pid, [target: self()]})
      )

    assert {:ok, ^source, ^effects} = Agent.cmd(source, F.signal(%{directives: effects}))
    assert {:error, _} = Agent.cmd(source, F.signal(%{directives: effects ++ [:invalid]}))

    assert {:error, _} =
             Agent.cmd(source, F.signal(%{directives: [%Directive.Emit{signal: :invalid}]}))

    refute_received {:signal, _}
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I18"]
  test "Plugin preparation and reduction preserve declaration order and state ownership" do
    source =
      F.instance(
        extensions: Enum.map([F.First, F.Second, F.Stateless, F.PreparedOnly], &F.contribution/1)
      )

    signal = F.signal()
    assert {:ok, candidate, []} = Agent.cmd(source, signal, context: %{observer: self()})
    assert candidate.state === %{source.state | first: 1, second: 1}
    assert_receive {:prepare, %{plugin: F.First}}
    assert_receive {:prepare, %{plugin: F.Second}}
    assert_receive {:executed, _, context}
    assert context.plugin_inputs[F.First].prepared === {0, signal.id}
    assert context.plugin_inputs[F.Second].prepared === {0, signal.id}
    assert context.plugin_inputs[F.PreparedOnly].prepared === nil
    assert_receive {:reduce, first}
    assert_receive {:reduce, second}
    assert first.state_before === source.state
    assert second.state === %{source.state | first: 1}
    assert {:error, _} = Agent.cmd(source, F.signal(%{output: %{source.state | first: 99}}))
  end

  @tag obligation: ["jido.agent.I18", "jido.agent.I23"]
  test "Plugin rejections retain application reasons and callback faults retain causes" do
    for {opts, reason} <- [
          {%{prepare: :reject}, :plugin_rejection},
          {%{reduce: :reject}, :reduction_rejection}
        ] do
      source = F.instance(extensions: [F.contribution(F.First, opts)])
      assert {:error, ^reason} = Agent.cmd(source, F.signal())
    end

    for opts <- [
          %{prepare: :raise},
          %{reduce: :raise},
          %{prepare: :invalid},
          %{reduce: :wrong_type},
          %{prepare: :nonportable}
        ] do
      source = F.instance(extensions: [F.contribution(F.First, opts)])
      assert {:error, %{__exception__: true, message: message}} = Agent.cmd(source, F.signal())
      assert is_binary(message) and message != ""
    end
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I18", "jido.agent.I19"]
  test "owned custom directives validate before reduction and retain order" do
    source = F.instance(extensions: [F.contribution(F.Effects)])
    directives = [%F.Effect{value: 7}, Directive.emit(F.signal()), %F.Effect{value: 9}]
    assert {:ok, candidate, ^directives} = Agent.cmd(source, F.signal(%{directives: directives}))
    assert candidate.state.effects == 16
    assert {:error, _} = Agent.cmd(F.instance(), F.signal(%{directives: directives}))
    assert {:error, _} = Agent.cmd(source, F.signal(%{directives: [%F.Effect{value: -1}]}))
  end

  @tag obligation: ["jido.agent.I17", "jido.agent.I19", "jido.agent.I23"]
  test "failure does not undo Action work and malformed routing remains structured" do
    source = F.instance()
    assert {:error, _} = Agent.cmd(source, F.signal(%{output: %{}}), context: %{observer: self()})
    assert_receive {:executed, _, _}

    assert {:error, %Agent.Error{code: :unmatched_input}} =
             Agent.cmd(source, F.signal(%{}, "missing"))

    assert {:error, %{__exception__: true}} = Agent.cmd(source, %{F.signal() | type: nil})
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal())
  end

  @tag obligation: ["jido.agent.I6", "jido.agent.I12"]
  test "Action contracts are read again after code reload" do
    name = "Reload#{System.unique_integer([:positive])}"
    action = Module.concat(__MODULE__, name)
    host = Module.concat(action, Host)

    source = """
    defmodule #{inspect(action)} do
      use Jido.Action, name: "reload_action", schema: Zoi.object(%{value: Zoi.integer()})
      def run(_, context), do: {:ok, context.agent_state}
    end
    defmodule #{inspect(host)} do
      use Jido.Agent, name: "reload_host"
      routes do
        route "test.run", #{inspect(action)}
      end
    end
    """

    JidoTest.AuthoringCompiler.with_compiled(
      source,
      fn _ ->
        agent = host.instantiate!(id: "reload")
        assert {:ok, ^agent, []} = Agent.cmd(agent, F.signal(%{value: 1}))
        :code.purge(action)
        :code.delete(action)

        Code.compile_string("""
        defmodule #{inspect(action)} do
          use Jido.Action, name: "reload_action", schema: Zoi.object(%{value: Zoi.string()})
          def run(_, context), do: {:ok, context.agent_state}
        end
        """)

        assert {:error, _} = Agent.cmd(agent, F.signal(%{value: 1}))
        assert {:ok, ^agent, []} = Agent.cmd(agent, F.signal(%{value: "current"}))
        assert {:ok, _} = host.instantiate(id: "new")
      end,
      modules: [action, host]
    )
  end
end

defmodule JidoTest.Contract.AgentExecutionTest do
  use Covenant.Case, component: "jido.agent", async: false

  alias Jido.Agent
  alias Jido.Agent.{Directive, Turn}
  alias Jido.Error.{ExecutionError, RoutingError, ValidationError}
  alias JidoTest.AgentContract, as: F

  @tag obligation: ["jido.agent.I12", "jido.agent.I13"]
  test "Router priority selects one Action or Flow and merges defaults shallowly" do
    source =
      F.instance(
        routes: [
          {"test.*", {F.Return, %{low: true}}, priority: -5},
          {"test.run", {F.Return, %{amount: 1, nested: %{a: 1, b: 2}, flag: true}}, priority: 8},
          {"test.flow", F.Flow}
        ]
      )

    signal = F.signal(%{amount: 7, nested: %{a: 9}, flag: false})

    assert {:ok, %Turn{executable: F.Return, input: input, source_signal: ^signal}} =
             Agent.handle_signal(signal, source)

    assert input === %{amount: 7, nested: %{a: 9}, flag: false}
    assert {:ok, ^source, []} = Agent.cmd(source, signal, context: %{observer: self()})

    assert_receive {:executed, ^input,
                    %{signal: ^signal, agent_id: "contract-instance", agent_state: state}}

    assert state === source.state

    assert {:ok, %{state: %{count: 4}}, []} =
             Agent.cmd(source, F.signal(%{amount: 4}, "test.flow"))
  end

  @tag obligation: ["jido.agent.I12", "jido.agent.I14"]
  test "custom selection accepts normalized input and binds only the original Signal" do
    source = F.instance(module: F.Selection)
    signal = F.signal(%{})

    for input <- [%{a: 2}, [a: 1, a: 2], nil] do
      Process.put(:contract_selection, fn _ -> Turn.new(F.Return, input) end)
      assert {:ok, ^source, []} = Agent.cmd(source, signal, context: %{observer: self()})
      expected = if input == nil, do: %{}, else: Map.new(input)
      assert_receive {:executed, ^expected, %{signal: ^signal}}
    end

    wrong = F.signal()

    Process.put(
      :contract_selection,
      {:ok, %Turn{executable: F.Return, input: %{}, source_signal: wrong}}
    )

    assert {:error,
            %ValidationError{
              details: %{expected_signal_id: id, turn_signal_id: wrong_id}
            }} = Agent.cmd(source, signal)

    assert id == signal.id
    assert wrong_id == wrong.id

    Process.put(
      :contract_selection,
      {:ok, %Turn{executable: F.Return, input: %{}, source_signal: signal}}
    )

    assert {:ok, ^source, []} = Agent.cmd(source, signal)
    Process.put(:contract_selection, {:ok, %Turn{executable: F.Return, source_signal: :invalid}})
    assert {:error, %ValidationError{}} = Agent.cmd(source, signal)
  end

  @tag obligation: ["jido.agent.I14", "jido.agent.I13"]
  test "map, duplicate keyword, and nil Signal data retain input and source semantics" do
    source = F.instance(routes: [{"test.run", {F.Return, %{amount: 3}}}])

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
      assert {:error, %ValidationError{}} =
               Agent.cmd(source, F.signal(data), context: %{observer: self()})
    end

    # A final synchronous command proves the invalid inputs did not reach the Action.
    assert {:ok, ^source, []} =
             Agent.cmd(source, F.signal(%{marker: :last}), context: %{observer: self()})

    assert_receive {:executed, %{marker: :last}, _}
    refute_received {:executed, _, _}
  end

  @tag obligation: "jido.agent.I15"
  test "reserved caller keys fail and allowed context preserves exact values" do
    source = F.instance()

    for key <- [:agent_id, :agent_state, :plugin_inputs, :signal] do
      assert {:error, %ValidationError{}} =
               Agent.cmd(source, F.signal(), context: %{key => :forged})
    end

    for context <- [nil, [], [request: 1, request: 2], %{request: 2}] do
      assert {:ok, ^source, []} = Agent.cmd(source, F.signal(), context: context)
    end

    signal = F.signal()

    assert {:ok, ^source, []} =
             Agent.cmd(source, signal, context: [observer: self(), request: 1, request: 2])

    assert_receive {:executed, %{}, context}

    assert context === %{
             observer: self(),
             request: 2,
             signal: signal,
             agent_id: source.id,
             agent_state: source.state,
             plugin_inputs: %{}
           }

    for opts <- [nil, %{}, [:invalid], [1 | :tail]],
        do: assert({:error, %ValidationError{}} = Agent.cmd(source, signal, opts))

    for context <- [1, [:invalid], %URI{}],
        do: assert({:error, %ValidationError{}} = Agent.cmd(source, signal, context: context))
  end

  @tag obligation: "jido.agent.I15"
  test "direct execution forwards policy options to the executor" do
    source = F.instance()
    signal = F.signal()

    for options <- [[timeout: -1], [max_attempts: 0], [backoff: :invalid]] do
      assert {:error, %Jido.Action.Error.ConfigurationError{}} =
               Agent.cmd(source, signal, options)
    end

    assert {:ok, ^source, []} =
             Agent.cmd(source, signal, timeout: 1_000, max_attempts: 2, backoff: :none)
  end

  @tag obligation: ["jido.agent.I9", "jido.agent.I16", "jido.agent.I17"]
  test "complete candidates preserve identity and failures do not damage the next command" do
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
      assert source.state.count == 0
    end

    assert {:error,
            %Jido.Action.Error.ExecutionFailureError{details: %{reason: :application_rejection}}} =
             Agent.cmd(source, F.signal(%{mode: :error}))

    output = %{source.state | count: 3, enabled: false, note: nil}
    assert {:ok, candidate, []} = Agent.cmd(source, F.signal(%{output: output}))
    assert candidate === %{source | state: output}
    assert Agent.definition(candidate) === Agent.definition(source)
    assert source.state.count == 0

    assert {:ok, %{state: %{count: 5}}, []} =
             Agent.cmd(candidate, F.signal(%{output: %{output | count: 5}}))
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I19"]
  test "Directives return in order without dispatch and the entire list must be valid" do
    source = F.instance()

    first = %Directive.Emit{
      signal: F.signal(%{effect: 1}, "effect.first"),
      dispatch: {:pid, [target: self()]}
    }

    second = %Directive.Emit{
      signal: F.signal(%{effect: 2}, "effect.second"),
      dispatch: {:pid, [target: self()]}
    }

    directives = [first, second]
    assert {:ok, ^source, ^directives} = Agent.cmd(source, F.signal(%{directives: directives}))
    refute_received {:signal, _}

    assert {:error, %ValidationError{}} =
             Agent.cmd(source, F.signal(%{directives: [first, :invalid]}))

    assert {:error, %ValidationError{}} =
             Agent.cmd(source, F.signal(%{directives: [%Directive.Emit{signal: :invalid}]}))

    assert {:error, %ValidationError{}} = Agent.cmd(source, F.signal(%{directives: [%URI{}]}))
    refute_received {:signal, _}
  end

  @tag obligation: ["jido.agent.I18", "jido.agent.I16"]
  test "Plugin preparation and reduction use declaration order and package-owned inputs" do
    source = F.instance(plugins: [F.First, F.Second, F.Stateless, F.PreparedOnly])
    signal = F.signal()
    assert {:ok, candidate, []} = Agent.cmd(source, signal, context: %{observer: self()})
    assert candidate.state === %{source.state | first: 1, second: 1}
    assert_receive {:prepare, first}
    assert_receive {:prepare, second}

    assert {first.plugin, first.plugin_state, first.agent_state, first.signal, first.agent_id,
            first.agent_module} ===
             {F.First, 0, source.state, signal, source.id, Agent}

    assert second.plugin == F.Second
    assert_receive {:executed, _, context}
    assert context.plugin_inputs[F.First].prepared === {0, signal.id}
    assert context.plugin_inputs[F.Second].prepared === {0, signal.id}
    assert context.plugin_inputs[F.PreparedOnly].prepared === nil

    assert Map.keys(context.plugin_inputs) |> Enum.sort() ==
             Enum.sort([F.First, F.Second, F.PreparedOnly])

    assert_receive {:reduce, first_reduction}
    assert_receive {:reduce, second_reduction}
    assert first_reduction.state === source.state
    assert second_reduction.state === %{source.state | first: 1}
    assert first_reduction.state_before === source.state
    assert first_reduction.prepared_input === {0, signal.id}
    assert first_reduction.directives == []
    assert first_reduction.signal == signal
    assert first_reduction.agent_id == source.id
    assert first_reduction.agent_module == Agent
  end

  @tag obligation: "jido.agent.I18"
  test "Plugin failures stop later callbacks and executable ownership violations fail" do
    for {stage, mode} <- [
          {:prepare, :reject},
          {:prepare, :invalid},
          {:prepare, :nonportable},
          {:prepare, :raise},
          {:reduce, :reject},
          {:reduce, :invalid},
          {:reduce, :wrong_type},
          {:reduce, :raise}
        ] do
      source = F.instance(plugins: [{F.First, [{stage, mode}]}, F.Second])
      assert {:error, _} = Agent.cmd(source, F.signal(), context: %{observer: self()})
      assert_receive {:prepare, %{plugin: F.First}}

      if stage == :prepare do
        refute_received {:prepare, %{plugin: F.Second}}
        refute_received {:executed, _, _}
      else
        assert_receive {:prepare, %{plugin: F.Second}}
        assert_receive {:executed, _, _}
        assert_receive {:reduce, %{plugin: F.First}}
        refute_received {:reduce, %{plugin: F.Second}}
      end

      assert source.state.first == 0
    end

    source = F.instance(plugins: [F.First])

    for output <- [%{source.state | first: 1}, Map.delete(source.state, :first)] do
      assert {:error, %ExecutionError{details: %{code: :plugin_state_owner_violation}}} =
               Agent.cmd(source, F.signal(%{output: output}))

      assert_receive {:prepare, _}
      refute_received {:reduce, _}
    end
  end

  @tag obligation: ["jido.agent.I19", "jido.agent.I17"]
  test "failure returns no candidate but cannot undo completed Action work" do
    source = F.instance()
    assert {:error, _} = Agent.cmd(source, F.signal(%{output: %{}}), context: %{observer: self()})
    assert_receive {:executed, %{output: %{}}, _}
    assert source.state.count == 0
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal())
  end

  @tag obligation: "jido.agent.I23"
  test "routing errors preserve structured causes, target, and retry hints" do
    source = F.instance()

    assert {:error, %RoutingError{target: "missing"}} =
             Agent.cmd(source, F.signal(%{}, "missing"))

    assert {:error, %RoutingError{}} = Agent.cmd(source, %{F.signal() | type: nil})
    custom = F.instance(module: F.Selection)

    for retry <- [true, false] do
      cause =
        Jido.Signal.Error.routing_error("route unavailable", %{
          target: "declared",
          retry: retry,
          reason: :offline
        })

      Process.put(:contract_selection, {:error, cause})
      assert {:error, %RoutingError{} = error} = Agent.cmd(custom, F.signal())
      assert error.message == cause.message
      assert error.target == "declared"
      assert error.details.cause === cause
      assert error.details.reason == :offline
      assert Jido.Error.retryable?(error) == retry
    end
  end

  @tag obligation: "jido.agent.I23"
  test "callback faults retain their cause and application error values pass through" do
    source = F.instance(module: F.Selection)

    for {kind, fun} <- [
          error: fn _ -> raise ArgumentError, "callback fault" end,
          throw: fn _ -> throw(:callback_fault) end,
          exit: fn _ -> exit(:callback_fault) end
        ] do
      Process.put(:contract_selection, fun)
      assert {:error, %ExecutionError{details: details}} = Agent.cmd(source, F.signal())
      assert details.code == :agent_callback_failed
      assert details.module == F.Selection
      assert details.callback == :handle_signal
      assert details.kind == kind

      if kind == :error,
        do: assert(match?(%ArgumentError{message: "callback fault"}, details.reason)),
        else: assert(details.reason == :callback_fault)
    end

    for reason <- [:application_rejection, %{custom: 1}] do
      Process.put(:contract_selection, {:error, reason})
      assert {:error, ^reason} = Agent.cmd(source, F.signal())
    end

    for result <- [:invalid, {:ok, %{}}, {:ok, []}] do
      Process.put(:contract_selection, result)

      assert {:error,
              %ExecutionError{
                details: %{
                  code: :agent_invalid_callback_result,
                  callback: :handle_signal,
                  result: ^result
                }
              }} = Agent.cmd(source, F.signal())
    end
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I18", "jido.agent.I19"]
  test "owned custom Directives validate before any reduction and keep their order" do
    source = F.instance(plugins: [F.First, F.Effects])
    directives = [%F.Effect{value: 7}, %Directive.Emit{signal: F.signal()}, %F.Effect{value: 9}]
    assert {:ok, candidate, ^directives} = Agent.cmd(source, F.signal(%{directives: directives}))
    assert candidate.state === %{source.state | first: 1, effects: 16}
    assert_receive {:prepare, _}
    assert_receive {:reduce, %{directives: ^directives}}

    assert_receive {:effects_reduced,
                    %{directives: ^directives, prepared_input: nil, plugin_state: 0}}

    assert {:error, %ValidationError{}} =
             Agent.cmd(F.instance(), F.signal(%{directives: directives}))

    assert {:error, %ValidationError{}} =
             Agent.cmd(source, F.signal(%{directives: [%F.Effect{value: -1}]}))

    assert_receive {:prepare, _}
    refute_received {:reduce, _}
    refute_received {:effects_reduced, _}
  end

  @tag obligation: "jido.agent.I14"
  test "Turn constructors validate the full supplied source envelope" do
    for signal <- [
          %{F.signal() | id: nil},
          %{F.signal() | source: "bad source"},
          %{F.signal() | type: nil}
        ] do
      assert {:error, %ValidationError{subject: :source_signal}} = Turn.new(F.Return, %{}, signal)
    end

    assert {:error, %ValidationError{subject: :input}} =
             Turn.validate(%Turn{executable: F.Return, input: :invalid})
  end

  @tag obligation: "jido.agent.I23"
  test "built-in direct command faults have nonempty messages without fixed wording" do
    source = F.instance()
    signal = F.signal()

    for attrs <- [
          %{name: nil},
          %{description: 1},
          %{vsn: 0},
          %{metadata: []},
          %{module: Enum},
          %{schema: nil},
          %{plugins: [Enum]},
          %{plugins: [{F.First, [key: :count]}]},
          %{routes: :invalid},
          %{routes: [{"test.run", F.Return, defaults: %URI{}}]},
          %{routes: [[]]},
          %{routes: [{"test.run", F.Return, unknown: 1}]},
          %{state: nil},
          %{state: %{source.state | count: "bad"}},
          %{id: ""}
        ] do
      assert {:error, error} = Agent.cmd(struct(source, attrs), signal)
      assert is_binary(error.message) and byte_size(error.message) > 0
    end

    for {input, opts} <- [
          {%{output: %{}}, []},
          {%{output: %URI{}}, []},
          {%{directives: [:invalid]}, []},
          {%{directives: [%URI{}]}, []},
          {%{}, [context: %{signal: :invalid}]},
          {%{}, [context: :invalid]}
        ] do
      assert {:error, error} = Agent.cmd(source, F.signal(input), opts)
      assert is_binary(error.message) and byte_size(error.message) > 0
    end

    custom = F.instance(module: F.Selection)

    for result <- [
          :invalid,
          {:ok, %Turn{executable: F.Return, source_signal: F.signal()}},
          {:ok, %Turn{executable: F.Return, source_signal: :invalid}},
          fn _ -> raise "fault" end,
          fn _ -> throw(:fault) end,
          fn _ -> exit(:fault) end
        ] do
      Process.put(:contract_selection, result)
      assert {:error, %{__exception__: true} = error} = Agent.cmd(custom, signal)
      assert is_binary(error.message) and byte_size(error.message) > 0
    end
  end

  @tag obligation: ["jido.agent.I18", "jido.agent.I23"]
  test "Plugin callback rejections keep their application-owned reason" do
    for {opts, reason} <- [
          {[prepare: :reject], :plugin_rejection},
          {[reduce: :reject], :reduction_rejection}
        ] do
      source = F.instance(plugins: [{F.First, opts}])
      assert {:error, ^reason} = Agent.cmd(source, F.signal())
    end
  end

  @tag obligation: ["jido.agent.I18", "jido.agent.I23"]
  test "Plugin faults keep their callback cause and non-portable input path" do
    for callback <- [:prepare, :reduce] do
      source = F.instance(plugins: [{F.First, [{callback, :raise}]}])
      assert {:error, %ExecutionError{} = error} = Agent.cmd(source, F.signal())
      assert is_binary(error.message) and byte_size(error.message) > 0
      assert error.details.plugin == F.First
      assert error.details.callback == callback
      assert error.details.code == :plugin_callback_failed
      assert %RuntimeError{} = error.details.error
    end

    source = F.instance(plugins: [{F.First, [prepare: :nonportable]}])

    assert {:error, %ExecutionError{details: details, message: message}} =
             Agent.cmd(source, F.signal())

    assert is_binary(message) and byte_size(message) > 0
    assert details.code == :non_portable_term
    assert details.path == [:plugin_inputs, F.First, :prepared]
  end

  @tag obligation: "jido.agent.I23"
  test "Plugin validation faults have nonempty messages" do
    for opts <- [[prepare: :invalid], [reduce: :invalid], [reduce: :wrong_type]] do
      assert {:error, %ExecutionError{} = error} =
               Agent.cmd(F.instance(plugins: [{F.First, opts}]), F.signal())

      assert is_binary(error.message) and byte_size(error.message) > 0
      assert error.details.plugin == F.First
      assert error.details.code == :plugin_invalid_callback_result

      if opts[:reduce] == :wrong_type do
        assert is_list(error.details.issues) and error.details.issues != []
      else
        assert error.details.result == :invalid
      end
    end

    source = F.instance(plugins: [F.First])

    assert {:error, %ExecutionError{} = error} =
             Agent.cmd(source, F.signal(%{output: %{source.state | first: 5}}))

    assert is_binary(error.message) and byte_size(error.message) > 0
  end

  @tag obligation: ["jido.agent.I16", "jido.agent.I23"]
  test "invalid executable values identify the callback and rejected value" do
    source = F.instance()

    assert {:error,
            %ValidationError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                directive: :invalid
              }
            }} = Agent.cmd(source, F.signal(%{directives: [:invalid]}))

    output = %URI{}

    assert {:error,
            %ExecutionError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                output: ^output
              }
            }} = Agent.cmd(source, F.signal(%{output: output}))
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I12"]
  test "data definitions support a module that implements the callback without behavior metadata" do
    source = F.instance(module: F.BareSelection)
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal())
  end

  @tag obligation: ["jido.agent.I14", "jido.agent.I23"]
  test "direct default selection reports malformed Signal data" do
    source = F.instance()

    for data <- [:invalid, [1, 2], [1 | :tail]] do
      assert {:error, %ValidationError{subject: :data, message: message}} =
               Agent.handle_signal(F.signal(data), source)

      assert is_binary(message) and byte_size(message) > 0
    end
  end

  @tag obligation: ["jido.agent.I3", "jido.agent.I10", "jido.agent.I18"]
  test "a Plugin without an Agent facet adds no Agent state or input" do
    source = F.instance(plugins: [F.PassiveContributor])
    assert source.state === F.instance().state
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal(), context: %{observer: self()})
    assert_receive {:executed, _, context}
    assert context.plugin_inputs == %{}
  end
end

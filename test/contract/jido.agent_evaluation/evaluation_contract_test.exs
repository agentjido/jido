defmodule JidoTest.Contract.AgentEvaluationTest do
  use Covenant.Case, component: "jido.agent_evaluation", async: true
  alias Jido.Agent
  alias Jido.Agent.{Command, Directive, Runner, Turn}
  alias Jido.Signal
  alias JidoTest.AgentContract, as: F

  defmodule ForwardChild do
    use Jido.Agent, name: "evaluation_forward_child"
  end

  defmodule HandoffTarget do
    use Jido.Action,
      name: "evaluation_handoff_target",
      schema: Zoi.object(%{count: Zoi.integer()})

    def run(_input, _context), do: raise("Agent.cmd/3 must not run a Handoff successor")
  end

  defmodule HandoffSelector do
    use Jido.Action, name: "evaluation_handoff_selector"
    def run(%{count: count}, _context), do: {:handoff, %{count: count + 1}, HandoffTarget}
  end

  defmodule HandoffFlow do
    use Jido.Flow, name: "evaluation_handoff_flow"

    flow do
      handoff "next", selector: HandoffSelector, params: %{count: input(:count)}
      output result("next")
    end
  end

  defp route(path, target, opts \\ []),
    do:
      Map.merge(
        %{
          path: path,
          handler: %{kind: :action, target: target},
          state: %{source: :output, path: []}
        },
        Map.new(opts)
      )

  def transform(%Jido.Signal{} = signal),
    do: {:ok, %{signal | type: "effect.transformed", data: %{value: 2}}}

  def reject_transform(_signal), do: {:error, :transform_rejected}
  def invalid_transform(_signal), do: {:ok, %{type: "effect.transformed"}}
  def raise_transform(_signal), do: raise("transform failure")

  @tag obligation: [
         "jido.agent_evaluation.I1",
         "jido.agent_evaluation.I2",
         "jido.agent_evaluation.I4"
       ]
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
            %Runner.Prepared{
              turn: %Turn{
                executable: F.Return,
                input: %{amount: 7, nested: %{a: 9}},
                source_signal: ^signal
              }
            }} = Runner.prepare(source, signal, [])

    assert {:ok, ^source, []} = Agent.cmd(source, signal, context: %{observer: self()})
    assert_receive {:executed, %{amount: 7, nested: %{a: 9}}, %{signal: ^signal}}
    assert {:error, _} = Agent.cmd(source, F.signal(%{mode: :error}))
    refute_received {:executed, _, _}

    flow_source =
      F.instance(
        routes: [
          %{
            path: "test.run",
            handler: %{kind: :flow, target: F.Flow},
            state: %{source: :output, path: []}
          }
        ]
      )

    assert {:ok, flow_candidate, []} = Agent.cmd(flow_source, F.signal(%{amount: 2}))
    assert flow_candidate.state.count == 2
  end

  @tag obligation: "jido.agent_evaluation.I2"
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
      signal = F.signal(data)

      assert {:error,
              %Jido.Error.ValidationError{
                subject: :data,
                details: %{signal_id: signal_id, data: ^data}
              }} = Agent.cmd(source, signal, context: %{observer: self()})

      assert signal_id == signal.id
    end

    refute_received {:executed, _, _}
  end

  @tag obligation: "jido.agent_evaluation.I3"
  test "reserved context fails and valid caller context and execution options are retained" do
    source = F.instance()

    for key <- [
          :agent_id,
          :agent_signal_source,
          :agent_state,
          :agent_topology,
          :plugin_inputs,
          :signal,
          :__jido_exec_durable__,
          :__jido_wait_host__,
          :__jido_wait_result__
        ] do
      assert {:error, _} = Agent.cmd(source, F.signal(), context: %{key => :forged})
    end

    signal = F.signal()

    assert {:ok, ^source, []} = Agent.cmd(source, signal, context: nil)

    assert {:ok, ^source, []} =
             Agent.cmd(source, signal, context: [observer: self(), request: 1, request: 2])

    assert_receive {:executed, %{}, keyword_context}
    assert keyword_context.request == 2

    for context <- [:invalid, "bad", [1, 2], %URI{}] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Agent.cmd(source, signal, context: context)
    end

    assert {:ok, ^source, []} =
             Agent.cmd(source, signal,
               context: %{observer: self(), request: 2},
               timeout: 1000,
               max_attempts: 2,
               backoff: :none
             )

    assert_receive {:executed, %{}, context}
    assert context.request == 2
    assert context.signal === signal
    state = context.agent_state
    assert state === source.state
    assert context.agent_id == source.id
    assert context.agent_signal_source == source.signal_source
    assert context.agent_topology === source.topology
    assert context.plugin_inputs == %{}

    for options <- [[timeout: -1], [max_attempts: 0], [backoff: :invalid]] do
      assert {:error, %Jido.Action.Error.ConfigurationError{}} =
               Agent.cmd(source, signal, options)
    end
  end

  @tag obligation: "jido.agent_evaluation.I5"
  test "success requires complete valid state and failure preserves the next command" do
    source = F.instance()

    for output <- [Map.delete(source.state, :count), %{source.state | count: "1"}] do
      assert {:error, %Agent.Error{code: code}} =
               Agent.cmd(source, F.signal(%{output: output}))

      assert code in [:incomplete_state, :invalid_state]
    end

    assert {:error, %Agent.Error{code: :invalid_state}} =
             Agent.cmd(source, F.signal(%{output: Map.put(source.state, :extra, 1)}))

    for output <- [[], nil, %URI{}] do
      assert {:error, %{__exception__: true}} =
               Agent.cmd(source, F.signal(%{output: output}))
    end

    assert {:error, _} = Agent.cmd(source, F.signal(%{mode: :error}))
    output = %{source.state | count: 3, enabled: false, note: nil}
    assert {:ok, candidate, []} = Agent.cmd(source, F.signal(%{output: output}))
    assert candidate === %{source | state: output}
    assert Agent.definition(candidate) === Agent.definition(source)
    assert source.state.count == 0
  end

  @tag obligation: ["jido.agent_evaluation.I7", "jido.agent_evaluation.I9"]
  test "the complete Directive batch builds one candidate without dispatch" do
    source = F.instance()

    effects =
      Enum.map(
        ["first", "second"],
        &Directive.emit(F.signal(%{}, "effect." <> &1), {:pid, [target: self()]})
      )

    assert {:ok, ^source, ^effects} = Agent.cmd(source, F.signal(%{directives: effects}))

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                directive: :invalid
              }
            }} = Agent.cmd(source, F.signal(%{directives: effects ++ [:invalid]}))

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                directive: %{invalid: true}
              }
            }} = Agent.cmd(source, F.signal(%{directives: [%{invalid: true}]}))

    assert {:error, _} =
             Agent.cmd(source, F.signal(%{directives: [%Directive.Emit{signal: :invalid}]}))

    change =
      Directive.route_add("next", F.Return)

    output = %{source.state | count: 2}

    assert {:ok, candidate, [^change]} =
             Agent.cmd(source, F.signal(%{output: output, directives: [change]}))

    assert candidate.state == output
    assert Enum.map(candidate.routes, & &1.path) == ["test.run", "next"]
    assert source.state.count == 0

    refute_received {:signal, _}
  end

  @tag obligation: "jido.agent_evaluation.I7"
  test "one Reply must identify the current request as its cause" do
    source = F.instance()
    request = F.signal()
    output = F.signal(%{}, "reply.done")
    {:ok, correlated} = Signal.put_context(output, "jidocausationid", request.id)
    reply = Directive.reply(correlated)

    assert {:ok, ^source, [^reply]} =
             Agent.cmd(source, %{request | data: %{directives: [reply]}})

    {:ok, wrong} = Signal.put_context(output, "jidocausationid", "other-request")

    assert {:error,
            %Jido.Error.ValidationError{
              details: %{
                request_id: request_id,
                causation_id: "other-request",
                reply_id: reply_id
              }
            }} =
             Agent.cmd(source, %{
               request
               | data: %{directives: [Directive.reply(wrong)]}
             })

    assert request_id == request.id
    assert reply_id == wrong.id

    assert {:error, %Jido.Error.ValidationError{details: %{count: 2}}} =
             Agent.cmd(source, %{request | data: %{directives: [reply, reply]}})
  end

  @tag obligation: "jido.agent_evaluation.I9"
  test "one batch cannot change a Plugin and run its owned Directive" do
    assert {:error, _reason} =
             Agent.cmd(
               F.instance(),
               F.signal(%{
                 directives: [Directive.plugin_add(F.Effects), %F.Effect{value: 1}]
               })
             )

    assert {:ok, owned, _} =
             Agent.cmd(
               F.instance(),
               F.signal(%{directives: [Directive.plugin_add(F.Effects)]})
             )

    assert {:error, %{code: :plugin_change_with_owned_directive}} =
             Agent.cmd(
               owned,
               F.signal(%{
                 directives: [Directive.plugin_configure(F.Effects, []), %F.Effect{value: 1}]
               })
             )

    assert {:ok, next, [%F.Effect{}]} =
             Agent.cmd(owned, F.signal(%{directives: [%F.Effect{value: 1}]}))

    assert next.state.effects == 1
  end

  @tag obligation: ["jido.agent_evaluation.I7", "jido.agent_evaluation.I9"]
  test "emission requests normalize once without a route output contract" do
    source = F.instance(signal_source: "/contract")

    signal = F.signal(%{value: 1}, "effect.allowed")

    requests = [
      Directive.emit("effect.allowed", %{value: 1}),
      %{kind: :emit, signal: signal},
      Directive.emit(signal),
      Jido.AgentServer.Directive.parent_send(signal),
      Jido.AgentServer.Directive.agent_send(:child, signal)
    ]

    for request <- requests do
      assert {:ok, _, [_]} = Agent.cmd(source, F.signal(%{directives: [request]}))
    end

    assert {:ok, _, [%Directive.Emit{signal: output}]} =
             Agent.cmd(
               source,
               F.signal(%{directives: [Directive.emit("effect.allowed", %{value: 1})]})
             )

    assert output.type == "effect.allowed"
    assert output.source == source.signal_source
    assert output.data == %{value: 1}

    assert {:ok, _, [%Directive.RouteAdd{}]} =
             Agent.cmd(
               source,
               F.signal(%{
                 directives: [
                   Directive.route_add("next", F.Return)
                 ]
               })
             )

    for {request, code} <- [
          {%{kind: :emit, type: "effect.allowed", data: %{}, unknown: true}, :unknown_fields},
          {%{kind: :emit, type: "effect.*", data: %{}}, :wildcard_type},
          {%{kind: :emit, signal: %{type: "effect.allowed"}}, :invalid_directive}
        ] do
      assert {:error, %Agent.Error{code: ^code, path: [0]}} =
               Agent.cmd(source, F.signal(%{directives: [request]}))
    end

    for request <- [%{signal: signal}, %{type: "effect.allowed", data: %{}}] do
      assert {:error,
              %Jido.Error.ValidationError{
                details: %{
                  code: :agent_invalid_callback_result,
                  callback: :execute,
                  directive: ^request
                }
              }} = Agent.cmd(source, F.signal(%{directives: [request]}))
    end

    invalid_signal = %{signal | type: nil}

    assert {:error, %Agent.Error{code: :invalid_signal, path: [0], details: %{issues: issues}}} =
             Agent.cmd(
               source,
               F.signal(%{directives: [%{kind: :emit, signal: invalid_signal}]})
             )

    assert issues != []
  end

  @tag obligation: ["jido.agent_evaluation.I1", "jido.agent_evaluation.I4"]
  test "transform routes produce one Signal without rerouting" do
    input = F.signal(%{value: 1})

    transform =
      F.instance(
        routes: [
          %{
            path: "test.run",
            handler: %{kind: :transform, target: {__MODULE__, :transform, 1}}
          },
          route("effect.transformed", F.Add)
        ]
      )

    assert {:ok, ^transform, [%Directive.Emit{signal: output}]} = Agent.cmd(transform, input)
    assert output === %{input | type: "effect.transformed", data: %{value: 2}}

    for callback <- [:reject_transform, :invalid_transform, :raise_transform] do
      source =
        F.instance(
          routes: [
            %{
              path: "test.run",
              handler: %{kind: :transform, target: {__MODULE__, callback, 1}}
            }
          ]
        )

      assert {:error, %{__exception__: true} = error} = Agent.cmd(source, input)

      case callback do
        :reject_transform ->
          assert %Jido.Action.Error.ExecutionFailureError{
                   details: %{reason: :transform_rejected}
                 } = error

        :invalid_transform ->
          assert %Agent.Error{code: :invalid_result} = error

        :raise_transform ->
          assert %Jido.Action.Error.ExecutionFailureError{
                   details: %{exception: RuntimeError, phase: :run}
                 } = error
      end
    end
  end

  @tag obligation: ["jido.agent_evaluation.I1", "jido.agent_evaluation.I4"]
  test "forward routes return the unchanged Signal in one explicit Directive" do
    signal = F.signal()

    parent =
      F.instance(
        routes: [
          %{
            path: "test.run",
            handler: %{kind: :forward, target: %{kind: :parent}}
          }
        ]
      )

    assert {:ok, ^parent, [%Jido.AgentServer.Directive.ParentSend{signal: ^signal}]} =
             Agent.cmd(parent, signal)

    child =
      F.instance(
        routes: [
          %{
            path: "test.run",
            handler: %{kind: :forward, target: %{kind: :agent, name: :worker}}
          }
        ],
        topology: %{agents: [%{name: :worker, definition: ForwardChild}]}
      )

    assert {:ok, ^child, [%Jido.AgentServer.Directive.AgentSend{name: :worker, signal: ^signal}]} =
             Agent.cmd(child, signal)
  end

  @tag obligation: "jido.agent_evaluation.I9"
  test "Agent.cmd returns a terminal Handoff without running its successor" do
    source =
      F.instance(
        routes: [
          %{
            path: "test.run",
            handler: %{kind: :flow, target: HandoffFlow},
            state: %{source: :output, path: []}
          }
        ]
      )

    assert {:handoff, ^source,
            %Jido.Instruction{target: HandoffTarget, kind: :action, params: %{count: 5}}, []} =
             Agent.cmd(source, F.signal(%{count: 4}))
  end

  @tag obligation: ["jido.agent_evaluation.I1", "jido.agent_evaluation.I2"]
  test "Turn validation normalizes input and rejects source substitution" do
    source = F.signal()
    other = F.signal(%{}, "other")
    assert {:ok, unbound} = Turn.new(F.Return, nil)
    assert Turn.new!(F.Return, %{}).input == %{}
    assert {:ok, bound} = Turn.bind_source(unbound, source)
    assert {:ok, %Turn{input: %{}}} = Turn.validate_selected(bound)
    assert {:ok, ^bound} = Turn.bind_source(bound, source)
    assert {:error, %{__exception__: true}} = Turn.bind_source(bound, other)
    assert {:error, %{__exception__: true}} = Turn.new(F.Return, :invalid)
    assert {:error, %{__exception__: true}} = Turn.validate(:invalid)
  end

  @tag obligation: "jido.agent_evaluation.I10"
  test "the AgentServer evaluation boundary keeps stages closed" do
    source = F.signal()
    agent = F.instance()
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Agent.runtime_plugins(agent))
    {:ok, command} = Command.new(agent, source)
    assert {:ok, prepared} = Runner.prepare_for_server(command, source, [], specs)
    assert prepared.agent === agent
    assert prepared.turn.source_signal === source
    assert {:ok, ^agent, []} = Runner.finish_for_server(prepared, {:ok, agent.state})

    assert {:error, :compose,
            %Jido.Error.ExecutionError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                result: :invalid
              }
            }} =
             Runner.finish_for_server(prepared, :invalid)

    assert {:error, :compose,
            %Jido.Error.ExecutionError{
              details: %{
                code: :agent_invalid_callback_result,
                callback: :execute,
                output: []
              }
            }} =
             Runner.finish_for_server(prepared, {:ok, []})

    invalid = put_in(command.context, %{agent_id: "reserved"})

    assert {:error, :input, %{__exception__: true}} =
             Runner.prepare_for_server(invalid, source, [], specs)

    unrouted = F.signal(%{}, "missing")
    {:ok, command} = Command.new(agent, unrouted)

    assert {:error, :route, %Agent.Error{code: :unmatched_input}} =
             Runner.prepare_for_server(command, unrouted, [], specs)
  end

  @tag obligation: ["jido.agent_evaluation.I9", "jido.agent_evaluation.I10"]
  test "the AgentServer Handoff boundary keeps the successor Turn and candidate complete" do
    agent = F.instance()
    signal = F.signal(%{count: 1})
    {:ok, command} = Command.new(agent, signal, %{caller: :retained})
    {:ok, specs} = Jido.Plugin.Normalizer.normalize_all(Agent.runtime_plugins(agent))
    instruction = Jido.Instruction.new!(target: HandoffTarget, params: %{count: 2})

    assert {:ok,
            %Runner.Prepared{
              agent: ^agent,
              signal: ^signal,
              turn: %Turn{
                executable: ^instruction,
                input: %{},
                route: %{state: %{source: :output, path: []}, reply: nil},
                source_signal: ^signal
              },
              context: %{caller: :retained, signal: ^signal},
              exec_opts: [timeout: 10]
            } = prepared} =
             Runner.prepare_handoff_for_server(
               command,
               signal,
               instruction,
               [timeout: 10],
               specs
             )

    change = Directive.route_add("next", F.Return)

    assert {:handoff, candidate, ^instruction, [^change]} =
             Runner.finish_for_server(prepared, {:handoff, instruction, [change]})

    assert Enum.map(candidate.routes, & &1.path) == ["test.run", "next"]
  end

  @tag obligation: ["jido.agent_evaluation.I6", "jido.agent_evaluation.I8"]
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
    assert second.candidate_state === %{source.state | first: 1}

    assert {:error,
            %Jido.Error.ExecutionError{
              details: %{code: :plugin_state_owner_violation, keys: [:first]}
            }} = Agent.cmd(source, F.signal(%{output: %{source.state | first: 99}}))
  end

  @tag obligation: ["jido.agent_evaluation.I6", "jido.agent_evaluation.I8"]
  test "Plugin rejections retain application reasons and callback faults retain causes" do
    for {opts, reason} <- [
          {%{prepare: :reject}, :plugin_rejection},
          {%{reduce: :reject}, :reduction_rejection}
        ] do
      source = F.instance(extensions: [F.contribution(F.First, opts)])
      assert {:error, ^reason} = Agent.cmd(source, F.signal())
    end

    for {opts, code, callback} <- [
          {%{prepare: :raise}, :plugin_callback_failed, :prepare},
          {%{reduce: :raise}, :plugin_callback_failed, :reduce},
          {%{prepare: :invalid}, :plugin_invalid_callback_result, nil},
          {%{reduce: :invalid}, :plugin_invalid_callback_result, nil},
          {%{reduce: :wrong_type}, :plugin_invalid_callback_result, nil},
          {%{prepare: :nonportable}, :non_portable_term, nil}
        ] do
      source = F.instance(extensions: [F.contribution(F.First, opts)])

      assert {:error, %Jido.Error.ExecutionError{details: details}} =
               Agent.cmd(source, F.signal())

      assert Jido.Error.code(%{details: details}) == code
      assert details.plugin == F.First
      if callback, do: assert(details.callback == callback)

      case opts do
        %{prepare: :nonportable} ->
          assert details.path == [:plugin_inputs, F.First, :prepared]

        %{prepare: :invalid} ->
          assert details.result == :invalid

        %{reduce: :invalid} ->
          assert details.result == :invalid

        %{reduce: :wrong_type} ->
          assert details.issues != []

        _ ->
          :ok
      end
    end
  end

  @tag obligation: ["jido.agent_evaluation.I7", "jido.agent_evaluation.I8"]
  test "owned custom directives validate before reduction and retain order" do
    source = F.instance(extensions: [F.contribution(F.Effects)])
    directives = [%F.Effect{value: 7}, Directive.emit(F.signal()), %F.Effect{value: 9}]
    assert {:ok, candidate, ^directives} = Agent.cmd(source, F.signal(%{directives: directives}))
    assert candidate.state.effects == 16
    assert_receive {:effects_reduced, _}

    assert {:error, %Jido.Error.ValidationError{details: %{directive: %F.Effect{value: 7}}}} =
             Agent.cmd(F.instance(), F.signal(%{directives: directives}))

    assert {:error, _} = Agent.cmd(source, F.signal(%{directives: [%F.Effect{value: -1}]}))
    refute_received {:effects_reduced, _}
  end

  @tag obligation: [
         "jido.agent_evaluation.I1",
         "jido.agent_evaluation.I5",
         "jido.agent_evaluation.I9"
       ]
  test "failure does not undo Action work and malformed routing remains structured" do
    source = F.instance()
    assert {:error, _} = Agent.cmd(source, F.signal(%{output: %{}}), context: %{observer: self()})
    assert_receive {:executed, _, _}

    assert {:error, %Agent.Error{code: :unmatched_input}} =
             Agent.cmd(source, F.signal(%{}, "missing"))

    assert {:error, %{__exception__: true}} = Agent.cmd(source, %{F.signal() | type: nil})
    assert {:ok, ^source, []} = Agent.cmd(source, F.signal())
  end

  @tag obligation: "jido.agent_evaluation.I4"
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

defmodule Jido.Agent.StatelessDirectiveTest do
  use JidoTest.Case, async: true

  alias Jido.AgentServer, as: Server
  alias Jido.Signal

  defmodule Effect do
    @schema Zoi.struct(__MODULE__, %{kind: Zoi.enum([:reply, :block, :last])}, coerce: true)
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
    def schema, do: @schema
  end

  defmodule Effects do
    use Jido.Plugin

    @impl true
    def directives(_opts), do: [Effect]

    @impl true
    def validate_directive(effect, _opts),
      do: Zoi.parse(Effect.schema(), Map.from_struct(effect))

    @impl true
    def dispatch(nil, %Effect{kind: kind}, context, _opts) do
      observer = context.turn_context.observer
      send(observer, {:effect_started, kind, self()})

      case kind do
        :reply ->
          server =
            Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

          Server.cast(server, Signal.new!("effect.result", %{value: 8}, source: "/effect"))

        :block ->
          receive do
            :release -> :ok
          end

        :last ->
          :ok
      end
    end
  end

  defmodule Submit do
    use Jido.Action,
      name: "stateless_directive_submit",
      schema: Zoi.object(%{kind: Zoi.enum([:reply, :block])})

    @impl true
    def run(%{kind: kind}, %{agent_state: state}),
      do: {:ok, %{state | value: 7}, [%Effect{kind: kind}, %Effect{kind: :last}]}
  end

  defmodule Result do
    use Jido.Action,
      name: "stateless_directive_result",
      schema: Zoi.object(%{value: Zoi.integer()})

    @impl true
    def run(%{value: value}, %{agent_state: state}), do: {:ok, %{state | value: value}}
  end

  defmodule Agent do
    use Jido.Agent,
      name: "stateless_directive_agent",
      schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
      routes: [{"effect.submit", Submit}, {"effect.result", Result}],
      plugins: [Effects]
  end

  test "a handler without a Plugin process sends its result through another Turn", %{jido: jido} do
    {:ok, server} = Jido.start_agent(jido, Agent)
    refute Map.has_key?(Server.children(server), {:plugin, Effects})

    assert {:ok, committed} =
             Server.call(server, signal("effect.submit", %{kind: :reply}),
               context: %{observer: self()}
             )

    assert committed.state == %{value: 7}
    assert_receive {:effect_started, :reply, worker}
    refute worker == server
    assert_receive {:effect_started, :last, _}
    eventually(fn -> Server.snapshot(server).state_version == 2 end)
    assert Server.agent(server).state == %{value: 8}
  end

  test "timeout and task death preserve the commit and stop later dispatch", %{jido: jido} do
    observer = self()

    for failure <- [:timeout, :killed] do
      policy = fn reason, outcome ->
        send(observer, {:effect_failed, reason, outcome})
        :continue
      end

      {:ok, server} =
        Jido.start_agent(jido, Agent,
          directive_timeout: if(failure == :timeout, do: 100, else: 5_000),
          error_policy: policy
        )

      assert {:ok, committed} =
               Server.call(server, signal("effect.submit", %{kind: :block}),
                 context: %{observer: observer}
               )

      assert_receive {:effect_started, :block, worker}
      monitor = Process.monitor(worker)
      assert %{phase: :directing} = Server.status(server)
      assert {:error, :directing} = Server.cancel(server)
      assert {:error, :stale_turn} = Server.cancel_turn(server, "stale")
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
      if failure == :killed, do: Process.exit(worker, :kill)

      {:effect_failed, _reason, outcome} =
        try do
          assert_receive {:effect_failed, _reason, _outcome}, 1_000
        rescue
          error in ExUnit.AssertionError ->
            # Preserve process state when the assertion fails.
            # credo:disable-for-next-line Credo.Check.Warning.IoInspect
            IO.inspect(
              {failure,
               Process.info(server, [:current_stacktrace, :message_queue_len, :messages])},
              label: "directive failure diagnostics"
            )

            reraise error, __STACKTRACE__
        end

      assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 1_000
      assert outcome.committed?
      assert outcome.stage == :directive

      assert outcome.directives == %{
               completed: 0,
               failed: 1,
               failed_index: 0,
               skipped: 1,
               total: 2
             }

      eventually(fn -> Server.status(server).phase == :idle end)
      assert Server.snapshot(server) == %{agent: committed, state_version: 1}
      refute_received {:effect_started, :last, _}

      assert {:ok, next} = Server.call(server, signal("effect.result", %{value: 9}))
      assert Server.snapshot(server) == %{agent: next, state_version: 2}
    end
  end
end

defmodule JidoTest.Property.Runtime.LifecycleModelTest do
  use JidoTest.Case, async: false
  use ExUnitProperties

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server

  defmodule Add do
    use Jido.Action,
      name: "runtime_property_add",
      schema: Jido.Joi.object(%{delta: Jido.Joi.integer()})

    @impl true
    def run(%{delta: delta}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + delta, history: state.history ++ [delta]}}
    end
  end

  defmodule Mutate do
    use Jido.Action,
      name: "runtime_property_mutate",
      schema:
        Jido.Joi.object(%{
          mode: Jido.Joi.enum([:success, :failure, :invalid_state, :invalid_directive]),
          by: Jido.Joi.integer()
        })

    @impl true
    def run(%{mode: :success, by: by}, %{agent_state: state}) do
      {:ok, %{state | count: state.count + by, history: state.history ++ [by]}}
    end

    def run(%{mode: :failure}, _context),
      do: {:error, Jido.Error.execution_error("generated failure")}

    def run(%{mode: :invalid_state}, %{agent_state: state}),
      do: {:ok, %{state | count: "invalid"}}

    def run(%{mode: :invalid_directive}, %{agent_state: state}),
      do: {:ok, state, [:invalid]}
  end

  defmodule Counter do
    use Jido.Agent, name: "runtime_property_counter"

    state do
      schema Jido.Joi.object(%{
               count: Jido.Joi.integer() |> Jido.Joi.default(0),
               history: Jido.Joi.list(Jido.Joi.integer()) |> Jido.Joi.default([])
             })
    end

    routes do
      route "runtime.property.add", Add
      route "runtime.property.mutate", Mutate
    end
  end

  for {suite, runs} <- [{:property, 30}, {:fuzz, 300}] do
    @tag [{suite, true}, {:timeout, 180_000}]
    test "#{suite} generated histories preserve commit, recovery, and cleanup", c do
      step =
        StreamData.fixed_map(%{
          mode: StreamData.member_of([:success, :failure, :invalid_state, :invalid_directive]),
          by: StreamData.integer(-100..100)
        })

      history = StreamData.list_of(step, max_length: 20)
      initial = StreamData.integer(-1_000..1_000)

      check all(
              initial_count <- initial,
              steps <- history,
              max_runs: unquote(runs),
              max_run_time: 120_000
            ) do
        verify_history(c, initial_count, steps)
      end
    end
  end

  defp verify_history(c, initial_count, steps) do
    id = unique_id("runtime-property")
    path = Path.join(c.tmp_dir, id)
    persistence = {Jido.Persistence.File, path: path}

    {:ok, server} =
      JidoTest.AgentServerAssertions.start_agent(c.jido, Counter,
        id: id,
        state: %{count: initial_count},
        persistence: persistence,
        persistence_mode: :create
      )

    expected =
      Enum.reduce(steps, %{count: initial_count, history: []}, fn step, model ->
        result = Server.call(server, signal("runtime.property.mutate", step))

        next_model =
          case step do
            %{mode: :success, by: by} ->
              expected = %{count: model.count + by, history: model.history ++ [by]}
              assert {:ok, next, []} = result
              assert next.state == expected
              expected

            %{mode: mode} when mode in [:failure, :invalid_state, :invalid_directive] ->
              assert {:error, error} = result
              assert is_exception(error)
              model
          end

        assert Server.agent(server).state == next_model
        next_model
      end)

    assert Server.agent(server).state == expected
    monitor = Process.monitor(server)
    assert :ok = Jido.hibernate(c.jido, server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 5_000
    assert Jido.whereis_agent(c.jido, id) == nil

    assert {:ok, restored} = Jido.thaw(c.jido, Counter, id, persistence: persistence)
    assert :ok = Server.await_ready(restored)
    assert Server.agent(restored).state == expected
    assert :ok = Jido.stop_agent(c.jido, restored)
    assert Jido.whereis_agent(c.jido, id) == nil
    assert Jido.agent_count(c.jido) == 0
  end
end

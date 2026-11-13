Code.require_file("../support/fuzz.exs", __DIR__)

defmodule Jido.AgentServer.Property.LifecycleModelTest do
  use Jido.Test.Case, async: false

  @moduletag :tmp_dir

  alias Jido.AgentServer, as: Server
  alias Jido.Test.Property.Fuzz

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
    @tag [
      {suite, true},
      fuzz_id: "agent_server_lifecycle",
      max_runs: runs,
      max_run_time: 120_000,
      timeout: 180_000
    ]
    test "#{suite} generated histories preserve commit, recovery, and cleanup", c do
      step =
        StreamData.fixed_map(%{
          "mode" => StreamData.member_of(~w(success failure invalid_state invalid_directive)),
          "by" => StreamData.integer(-100..100)
        })

      generator =
        StreamData.fixed_map(%{
          "initial_count" => StreamData.integer(-1_000..1_000),
          "steps" => StreamData.list_of(step, max_length: 20)
        })

      examples = [
        %{
          "initial_count" => 0,
          "steps" =>
            for(
              mode <- ~w(success failure invalid_state invalid_directive),
              do: %{"mode" => mode, "by" => 1}
            )
        }
      ]

      Fuzz.check(
        "agent_server_lifecycle",
        generator,
        Map.to_list(c) ++ [examples: examples],
        fn %{"initial_count" => initial_count, "steps" => steps} ->
          verify_history(c, initial_count, steps)
        end
      )
    end
  end

  defp verify_history(c, initial_count, steps) do
    id = unique_id("runtime-property")
    path = Path.join(c.tmp_dir, id)
    persistence = {Jido.Persistence.File, path: path}
    c = Jido.Test.Case.restart_jido!(c, persistence)

    {:ok, server} =
      Jido.Test.AgentServer.Assertions.start_agent(c.jido, Counter,
        id: id,
        state: %{count: initial_count},
        persistence_mode: :create
      )

    {expected, observations} =
      Enum.reduce(steps, {%{count: initial_count, history: []}, MapSet.new()}, fn step, {model, observations} ->
        mode = String.to_existing_atom(step["mode"])
        result = Server.call(server, signal("runtime.property.mutate", %{mode: mode, by: step["by"]}))

        next_model =
          case step do
            %{"mode" => "success", "by" => by} ->
              expected = %{count: model.count + by, history: model.history ++ [by]}
              assert {:ok, %Jido.AgentServer.TurnResult{status: :committed}} = result
              assert Server.snapshot(server).agent.state == expected
              expected

            %{"mode" => mode} when mode in ~w(failure invalid_state invalid_directive) ->
              assert {:ok, %Jido.AgentServer.TurnResult{status: :failed, error: error}} = result
              assert is_exception(error)
              model
          end

        assert Server.snapshot(server).agent.state == next_model
        {next_model, MapSet.put(observations, step["mode"])}
      end)

    assert Server.snapshot(server).agent.state == expected
    monitor = Process.monitor(server)
    assert {:ok, %Jido.AgentServer.Snapshot{}} = Server.stop(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _reason}, 5_000
    assert Jido.whereis_agent(c.jido, id) == nil

    assert {:ok, restored} = Jido.thaw(c.jido, Counter, id)
    assert :ok = Server.await_ready(restored)
    assert Server.snapshot(restored).agent.state == expected
    assert :ok = Jido.stop_agent(c.jido, restored)
    assert Jido.whereis_agent(c.jido, id) == nil
    assert Jido.resident_agent_count(c.jido) == 0

    ["hibernate", "restore", "cleanup" | MapSet.to_list(observations)]
  end
end

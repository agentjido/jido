defmodule Jido.Examples.CausalTrace.Compute do
  @moduledoc false
  use Jido.Action,
    name: "example_causal_compute",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        slot: Zoi.enum([:left, :right]),
        value: Zoi.integer()
      })

  def run(input, %{agent_state: state}) do
    value = input.value * 2

    result =
      Jido.Examples.CausalTrace.collect_result_signal!(
        input: %{request_id: input.request_id, slot: input.slot, value: value}
      )

    {:ok, %{state | value: value}, [Jido.Agent.Directive.emit_to_parent(result)]}
  end
end

defmodule Jido.Examples.CausalTrace.Worker do
  @moduledoc false
  use Jido.Agent, name: "example_causal_worker"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/causality"

    route "causal.compute", Jido.Examples.CausalTrace.Compute do
      define :compute, args: [:request_id, :slot, :value]
    end
  end
end

defmodule Jido.Examples.CausalTrace.Begin do
  @moduledoc false
  use Jido.Action,
    name: "example_causal_begin",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.min(1),
        value: Zoi.integer(),
        node: Zoi.atom() |> Zoi.optional()
      })

  alias Jido.Agent.Directive
  alias Jido.Examples.CausalTrace.Worker

  def run(input, %{agent_state: %{request_id: ""} = state}) do
    directives =
      Enum.flat_map([:left, :right], fn slot ->
        [
          Directive.spawn_agent(Worker, slot, node: input[:node], restart: :temporary),
          Directive.emit_to_child(
            slot,
            Worker.compute_signal!(input.request_id, slot, input.value)
          )
        ]
      end)

    {:ok, %{state | request_id: input.request_id}, directives}
  end

  def run(_input, _context), do: {:error, :request_already_started}
end

defmodule Jido.Examples.CausalTrace.Collect do
  @moduledoc false
  use Jido.Action,
    name: "example_causal_collect",
    schema:
      Zoi.object(%{
        request_id: Zoi.string(),
        slot: Zoi.enum([:left, :right]),
        value: Zoi.integer()
      })

  def run(%{request_id: id} = input, %{agent_state: %{request_id: id} = state}) do
    {:ok, %{state | results: Map.put(state.results, input.slot, input.value)}}
  end

  def run(_input, _context), do: {:error, :unrelated_result}
end

defmodule Jido.Examples.CausalTrace do
  @moduledoc """
  OBS-02 probe: a parent sends work to two real child Agents.

  The Agents only return business state and Directives. They do not add trace
  fields or emit telemetry. An external EventProbe collects SDK events for the
  parent ID and the two child IDs (`parent/left` and `parent/right`).

  Pass `input: %{node: target_node}` to `start_work/4` to place both children
  on another Erlang node with the same Jido instance and compiled modules.
  """
  use Jido.Agent, name: "example_causal_parent"

  agent do
    schema Zoi.object(%{
             request_id: Zoi.string() |> Zoi.default(""),
             results: Zoi.map() |> Zoi.default(%{}),
             private: Zoi.string() |> Zoi.default("private-causal-agent-state")
           })
  end

  routes do
    signal_source "/examples/causality"

    route "causal.begin", __MODULE__.Begin do
      define :start_work, args: [:request_id, :value]
    end

    route "causal.result", __MODULE__.Collect do
      define :collect_result
    end

    route "jido.agent.child.*", Jido.Examples.KeepState
  end
end

defmodule Jido.Examples.RemoteCounter.Calculate do
  @moduledoc false
  use Jido.Action,
    name: "example_remote_counter_calculate",
    schema: Zoi.object(%{value: Zoi.integer(), request_id: Zoi.string()})

  def run(input, %{agent_state: state}) do
    result = Map.put(input, :executed_on, node())
    reply = Jido.Signal.new!("examples.remote.result", result, source: "/examples/remote/counter")
    {:ok, %{state | value: input.value}, [Jido.Agent.Directive.emit_to_parent(reply)]}
  end
end

defmodule Jido.Examples.RemoteCounter do
  @moduledoc false
  use Jido.Agent, name: "example_remote_counter"

  agent do
    schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/remote/counter"

    route "examples.remote.record" do
      action %{value: value},
        name: "example_remote_counter_record",
        schema: Zoi.object(%{value: Zoi.integer()}),
        context: context do
        {:ok, %{context.agent_state | value: value}}
      end

      define :record, args: [:value]
    end

    route "examples.remote.calculate", Jido.Examples.RemoteCounter.Calculate do
      define :calculate, args: [:value, :request_id]
    end
  end
end

defmodule Jido.Examples.RemoteParent.RequestChild do
  @moduledoc false
  use Jido.Action,
    name: "example_remote_parent_request_child",
    schema: Zoi.object(%{target_node: Zoi.atom()})

  def run(%{target_node: target}, %{agent_state: state}) do
    directive =
      Jido.Agent.Directive.spawn_agent(Jido.Examples.RemoteCounter, :worker,
        node: target,
        restart: :temporary
      )

    {:ok, state, [directive]}
  end
end

defmodule Jido.Examples.RemoteParent.RequestResult do
  @moduledoc false
  use Jido.Action,
    name: "example_remote_parent_request_result",
    schema: Zoi.object(%{value: Zoi.integer(), request_id: Zoi.string()})

  def run(input, %{agent_state: state}) do
    signal = Jido.Examples.RemoteCounter.calculate_signal!(input.value, input.request_id)
    {:ok, state, [Jido.Agent.Directive.emit_to_child(:worker, signal)]}
  end
end

defmodule Jido.Examples.RemoteParent do
  @moduledoc false
  use Jido.Agent, name: "example_remote_parent"

  agent do
    schema Zoi.object(%{result: Zoi.map() |> Zoi.default(%{})})
  end

  routes do
    signal_source "/examples/remote/parent"

    route "examples.remote.spawn", Jido.Examples.RemoteParent.RequestChild do
      define :request_child, args: [:target_node]
    end

    route "examples.remote.synchronize", Jido.Examples.KeepState do
      define :synchronize
    end

    route "examples.remote.request_result", Jido.Examples.RemoteParent.RequestResult do
      define :request_result, args: [:value, :request_id]
    end

    route "examples.remote.result" do
      action result, name: "example_remote_parent_store_result", context: context do
        {:ok, %{context.agent_state | result: result}}
      end
    end

    route "jido.agent.child.*", Jido.Examples.KeepState
  end
end

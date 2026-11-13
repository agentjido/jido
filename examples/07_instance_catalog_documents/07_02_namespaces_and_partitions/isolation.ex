defmodule Jido.Examples.InstanceIsolation.Counter do
  @moduledoc "A counter used to prove namespace and partition isolation."

  use Jido.Agent, name: "instance_isolation_counter"

  state do
    schema Jido.Joi.object(%{count: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/instance/isolation"

    route "examples.instance.isolation.increment", as: :increment do
      action %{}, context: context do
        {:ok, %{context.agent_state | count: context.agent_state.count + 1}}
      end
    end
  end
end

defmodule Jido.Examples.InstanceIsolation do
  @moduledoc "Builds scoped Agent references and sends one counter command."

  alias Jido.Signal

  def ref(instance, id, partition), do: Jido.agent_ref(instance, id, partition: partition)

  def increment(instance, ref) do
    signal =
      Signal.new!("examples.instance.isolation.increment", %{}, source: "/examples/instance/isolation")

    Jido.call(instance, ref, signal)
  end
end

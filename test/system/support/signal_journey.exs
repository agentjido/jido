defmodule JidoTest.System.JourneyAction do
  @moduledoc false
  use Jido.Action,
    name: "system_journey_project",
    schema: Zoi.object(%{effect_id: Zoi.string(), value: Zoi.integer()})

  def run(input, _context), do: {:ok, input}
end

defmodule JidoTest.System.JourneyFlow do
  @moduledoc false
  use Jido.Flow,
    name: "system_journey_flow",
    schema: Zoi.object(%{"effect_id" => Zoi.string() |> Zoi.min(1), "value" => Zoi.integer()})

  flow do
    step "double", params <- input() do
      # JSON keys are strings. Select known fields; do not create atoms from
      # untrusted input and do not assume an implicit envelope conversion.
      {:ok, %{effect_id: params["effect_id"], value: params["value"] * 2}}
    end

    step "project", action: JidoTest.System.JourneyAction, params: result("double")
    output result("project")
  end
end

defmodule JidoTest.System.JourneyCommit do
  @moduledoc false
  use Jido.Action, name: "system_journey_commit"

  def run(input, context) do
    # A Flow returns data, not Agent directives. The outer Action translates
    # its validated output into the complete candidate state and intent.
    with {:ok, output} <- Jido.Exec.run(JidoTest.System.JourneyFlow, input, context) do
      directive = struct!(Jido.Examples.RecoverableDelivery.Deliver, output)
      {:ok, %{context.agent_state | value: output.value}, [directive]}
    end
  end
end

for {name, durable} <- [{:NormalJourneyAgent, nil}, {:DurableJourneyAgent, "journey"}] do
  defmodule Module.concat(JidoTest.System, name) do
    @moduledoc false
    use Jido.Agent, name: Macro.underscore(to_string(name))
    @durable durable

    agent do
      schema Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)})

      plugin Jido.Examples.RecoverableDelivery.Output,
        config: [sink: JidoTest.RecoverableDeliverySink]

      plugin Jido.Plugin.Bus.Client,
        config: [bus: :journey, path: "system.journey", durable: @durable, retry_delay_ms: 60_000]
    end

    routes do
      route "system.journey", JidoTest.System.JourneyCommit

      route "examples.runtime.delivery.confirm" do
        action %{effect_id: id, value: value}, context: context do
          directive =
            struct!(Jido.Examples.RecoverableDelivery.Confirm, effect_id: id, value: value)

          {:ok, context.agent_state, [directive]}
        end
      end
    end
  end
end

defmodule JidoTest.System.AckStore do
  @moduledoc false
  @behaviour Jido.Signal.Bus.Store
  alias Jido.Signal.Bus.Store.Memory

  # Keep the real Memory store outside the Bus process. This proves replay
  # across a Bus activation, not storage durability across BEAM failure.
  def init(opts), do: {:ok, Keyword.fetch!(opts, :state)}
  def append(records, state), do: write(state, :append, [records])
  def read(opts, state), do: Agent.get(state, &Memory.read(opts, &1.store))
  def latest_cursor(state), do: Agent.get(state, &Memory.latest_cursor(&1.store))
  def list_subscriptions(state), do: Agent.get(state, &Memory.list_subscriptions(&1.store))
  def delete_subscription(id, state), do: write(state, :delete_subscription, [id])

  def put_subscription(subscription, state) do
    fail? =
      Agent.get_and_update(state, fn current ->
        fail? = current.fail_ack and subscription["cursor"] > 0
        {fail?, %{current | fail_ack: false}}
      end)

    if fail? do
      owner = Agent.get(state, & &1.owner)
      send(owner, {:ack_failed, self(), subscription["cursor"]})
      {:error, :system_ack_unavailable}
    else
      write(state, :put_subscription, [subscription])
    end
  end

  defp write(state, operation, args) do
    Agent.get_and_update(state, fn current ->
      case apply(Memory, operation, args ++ [current.store]) do
        {:ok, next} -> {{:ok, state}, %{current | store: next}}
        error -> {error, current}
      end
    end)
  end
end

defmodule Jido.Examples.Durable.Waterpark.Guest do
  @moduledoc "A durable park guest that is addressed only by Agent Address."

  use Jido.Agent, name: "waterpark_guest"

  state do
    schema Jido.Joi.object(%{
             visits: Jido.Joi.integer() |> Jido.Joi.default(0),
             status:
               Jido.Joi.enum([:idle, :approved, :timer_done])
               |> Jido.Joi.default(:idle)
           })
  end

  routes do
    signal_source "/examples/durable/waterpark"

    route "waterpark.visit" do
      action _input, context: context do
        {:ok, %{context.agent_state | visits: context.agent_state.visits + 1}}
      end
    end

    route "waterpark.reserve", Jido.Examples.Durable.Waterpark.Approval
    route "waterpark.timer", Jido.Examples.Durable.Waterpark.Timer
  end
end

defmodule Jido.Examples.Durable.Waterpark.Approval do
  @moduledoc "Waits for one matching approval Signal."

  use Jido.Flow,
    name: "waterpark_approval",
    schema: Jido.Joi.object(%{request_id: Jido.Joi.string()})

  flow do
    await "approved",
      event: "waterpark.approved",
      match: %{request_id: input(:request_id)}

    step "finish", _approval <- result("approved"), inline: [context: context] do
      {:ok, %{context.agent_state | status: :approved}}
    end

    output result("finish")
  end
end

defmodule Jido.Examples.Durable.Waterpark.Timer do
  @moduledoc "Waits for a local durable timer occurrence."

  use Jido.Flow, name: "waterpark_timer"

  flow do
    timer "wake", after_ms: 250

    step "finish", _wake <- result("wake"), inline: [context: context] do
      {:ok, %{context.agent_state | status: :timer_done}}
    end

    output result("finish")
  end
end

defmodule Jido.Examples.Durable.Waterpark do
  @moduledoc "Public helpers for the single-Instance Waterpark example."

  alias Jido.Agent.Address
  alias Jido.Examples.Durable.Waterpark.Guest

  def create_guests(instance, namespace, count) when is_integer(count) and count > 0 do
    Enum.map(1..count, fn number ->
      address = Address.new!(namespace: namespace, id: "guest-#{number}")
      {:ok, ^address} = Jido.create_agent(instance, address, Guest)
      address
    end)
  end

  def visit(instance, address),
    do: Jido.call(instance, address, signal("waterpark.visit", %{}))

  def reserve(instance, address, request_id),
    do: Jido.call(instance, address, signal("waterpark.reserve", %{request_id: request_id}))

  def approve(instance, address, request_id, signal_id \\ Jido.Id.uuid7()) do
    Jido.call(
      instance,
      address,
      signal("waterpark.approved", %{request_id: request_id}, id: signal_id)
    )
  end

  def timer(instance, address),
    do: Jido.call(instance, address, signal("waterpark.timer", %{}))

  def load(instance, namespace, count \\ 1_000) do
    refs = create_guests(instance, namespace, count)
    Enum.each(refs, fn address -> {:ok, _result} = visit(instance, address) end)
    refs
  end

  defp signal(type, data, opts \\ []) do
    Jido.Signal.new!(type, data, Keyword.put(opts, :source, "/examples/durable/waterpark"))
  end
end

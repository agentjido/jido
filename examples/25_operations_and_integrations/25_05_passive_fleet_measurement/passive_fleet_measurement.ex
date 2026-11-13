defmodule Jido.Examples.Operations.MeasuredFleetAgent do
  @moduledoc "A small durable Agent for a bounded passive-fleet measurement."

  use Jido.Agent, name: "operations_measured_fleet_agent"

  state do
    schema Jido.Joi.object(%{activations: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/operations/fleet"

    route "examples.operations.fleet.activate", as: :activate do
      action _input, context: context do
        {:ok, %{context.agent_state | activations: context.agent_state.activations + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Operations.PassiveFleetMeasurement do
  @moduledoc "Measures one bounded local activation and passivation run."

  alias Jido.Agent.Address
  alias Jido.Examples.Operations.MeasuredFleetAgent

  @doc "Creates logical Agents, activates them with bounded concurrency, and reports measurements."
  def run(instance, namespace, count, concurrency)
      when count > 0 and concurrency > 0 do
    refs = create(instance, namespace, count)
    residents_before = Jido.resident_agent_count(instance)
    memory_before = :erlang.memory(:total)
    activation_started = System.monotonic_time()

    samples =
      refs
      |> Task.async_stream(&activate(instance, &1),
        max_concurrency: concurrency,
        ordered: false,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, sample} -> sample end)

    activation_us = elapsed_us(activation_started)
    resident_peak = Jido.resident_agent_count(instance)
    passivation_started = System.monotonic_time()
    :ok = await_zero(instance, System.monotonic_time(:millisecond) + 5_000)
    passivation_us = elapsed_us(passivation_started)
    memory_after = :erlang.memory(:total)

    %{
      environment: %{
        architecture: :erlang.system_info(:system_architecture) |> List.to_string(),
        elixir: System.version(),
        otp: System.otp_release(),
        schedulers: System.schedulers_online()
      },
      inputs: %{
        concurrency: concurrency,
        logical_agents: count,
        store: "Jido.Persistence.ETS"
      },
      residents: %{before: residents_before, peak: resident_peak, after: 0},
      activation: %{
        elapsed_us: activation_us,
        agents_per_second: rate(count, activation_us),
        latency_us: percentiles(Enum.map(samples, & &1.elapsed_us))
      },
      passivation: %{
        elapsed_us: passivation_us,
        agents_per_second: rate(count, passivation_us)
      },
      memory_bytes: %{before: memory_before, after: memory_after},
      results: Enum.frequencies_by(samples, & &1.status)
    }
  end

  defp create(instance, namespace, count) do
    Enum.map(1..count, fn number ->
      address = Address.new!(namespace: namespace, id: "fleet-agent-#{number}")
      {:ok, ^address} = Jido.create_agent(instance, address, MeasuredFleetAgent)
      address
    end)
  end

  defp activate(instance, address) do
    {:ok, signal} = MeasuredFleetAgent.activate_signal(%{})
    started = System.monotonic_time()
    {:ok, result} = Jido.call(instance, address, signal)
    %{elapsed_us: elapsed_us(started), status: result.status}
  end

  defp await_zero(instance, deadline) do
    cond do
      Jido.resident_agent_count(instance) == 0 ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "passivation timeout"

      true ->
        receive do
        after
          10 -> await_zero(instance, deadline)
        end
    end
  end

  defp elapsed_us(started) do
    System.monotonic_time()
    |> Kernel.-(started)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp rate(count, elapsed_us), do: Float.round(count * 1_000_000 / max(elapsed_us, 1), 2)

  defp percentiles(values) do
    sorted = Enum.sort(values)

    %{
      p50: Enum.at(sorted, max(ceil(length(sorted) * 0.50) - 1, 0)),
      p95: Enum.at(sorted, max(ceil(length(sorted) * 0.95) - 1, 0)),
      maximum: List.last(sorted)
    }
  end
end

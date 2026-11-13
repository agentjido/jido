defmodule Jido.Examples.Observability.ActivationMeasurements.Agent do
  @moduledoc "A small durable Agent used for bounded fleet measurements."

  use Jido.Agent, name: "examples_observability_activation_measurements_agent"

  state do
    schema Jido.Joi.object(%{pings: Jido.Joi.integer() |> Jido.Joi.default(0)})
  end

  routes do
    signal_source "/examples/observability/activation_measurements"

    route "examples.observability.activation_measurements.ping", as: :ping do
      action _input, context: context do
        {:ok, %{context.agent_state | pings: context.agent_state.pings + 1}}
      end
    end
  end
end

defmodule Jido.Examples.Observability.ActivationMeasurements do
  @moduledoc "Measures a bounded passive Agent fleet through public APIs."

  alias Jido.Agent.Ref
  alias Jido.Examples.Observability.ActivationMeasurements.Agent

  @doc "Creates logical Agents without keeping an activation process resident."
  def create(instance, namespace, count) when is_integer(count) and count > 0 do
    Enum.map(1..count, fn number ->
      ref = Ref.new!(namespace: namespace, id: "measured-agent-#{number}")
      {:ok, ^ref} = Jido.create_agent(instance, ref, Agent)
      ref
    end)
  end

  @doc "Activates each Agent once and returns measured call samples."
  def activate(instance, refs) do
    Enum.map(refs, fn ref ->
      {:ok, signal} = Agent.ping_signal(%{})
      started_at = System.monotonic_time()
      {:ok, result} = Jido.call(instance, ref, signal)

      %{
        activation_id: result.agent_activation_id,
        elapsed_us: elapsed_us(started_at),
        ref: ref,
        status: result.status
      }
    end)
  end

  @doc "Waits for the measured instance to have no resident Agents."
  def await_passivation(instance, timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    started_at = System.monotonic_time()
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    case await_zero(instance, deadline) do
      :ok -> {:ok, elapsed_us(started_at)}
      {:error, _reason} = error -> error
    end
  end

  @doc "Builds a portable report with explicit inputs and environment data."
  def report(samples, residents, persistence_operations, memory) do
    durations = Enum.map(samples, & &1.elapsed_us)

    %{
      environment: %{
        elixir: System.version(),
        otp: System.otp_release(),
        schedulers: System.schedulers_online()
      },
      inputs: %{logical_agents: length(samples)},
      latency_us: %{
        maximum: Enum.max(durations),
        p50: percentile(durations, 0.50),
        p95: percentile(durations, 0.95)
      },
      memory_bytes: memory,
      persistence_operations: persistence_operations,
      residents: residents
    }
  end

  defp await_zero(instance, deadline) do
    if Jido.resident_agent_count(instance) == 0 do
      :ok
    else
      if System.monotonic_time(:millisecond) < deadline do
        receive do
        after
          10 -> await_zero(instance, deadline)
        end
      else
        {:error, :passivation_timeout}
      end
    end
  end

  defp elapsed_us(started_at) do
    System.monotonic_time()
    |> Kernel.-(started_at)
    |> System.convert_time_unit(:native, :microsecond)
  end

  defp percentile(values, fraction) do
    sorted = Enum.sort(values)
    index = max(ceil(length(sorted) * fraction) - 1, 0)
    Enum.at(sorted, index)
  end
end

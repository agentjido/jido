defmodule Jido.Examples.CustomSignalSelection do
  @moduledoc "Selects a custom Turn while preserving normal declared routes."

  alias Jido.Agent
  alias Jido.Agent.Turn
  alias Jido.Error
  alias Jido.Signal

  defmodule Add do
    @moduledoc "Adds one validated amount to Agent state."
    use Jido.Action,
      name: "basic_custom_signal_add",
      schema: Zoi.object(%{amount: Zoi.integer()})

    def run(%{amount: amount}, %{agent_state: state}),
      do: {:ok, %{state | count: state.count + amount}}
  end

  use Agent, name: "basic_custom_signal_selection"

  agent do
    schema Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  end

  routes do
    signal_source "/examples/basic/custom_signal_selection"
    route "examples.basic.custom_signal.normal", Add, as: :normal
    route "examples.basic.custom_signal.reject", Add
  end

  @impl Agent
  def handle_signal(
        %Signal{type: "examples.basic.custom_signal.raw", data: %{"amount" => raw}} = signal,
        _agent
      ) do
    case Integer.parse(raw) do
      {amount, ""} -> Turn.new(Add, %{amount: amount}, signal)
      _other -> {:error, Error.validation_error("raw amount must be an integer")}
    end
  end

  def handle_signal(%Signal{type: "examples.basic.custom_signal.reject"}, _agent),
    do: {:error, Error.validation_error("custom selection rejected the Signal")}

  def handle_signal(%Signal{} = signal, agent), do: Agent.handle_signal(signal, agent)

  @doc "Builds a Signal with raw string data for custom selection."
  def raw_signal!(amount) do
    Signal.new!(
      "examples.basic.custom_signal.raw",
      %{"amount" => amount},
      source: "/examples/basic/custom_signal_selection"
    )
  end
end

defmodule JidoTest.Authoring.Agents.Fixtures.CustomSelection do
  use Jido.Agent,
    name: "authoring_custom_selection",
    schema: Zoi.object(%{text: Zoi.string() |> Zoi.default("")})

  @impl Jido.Agent
  def handle_signal(%Jido.Signal{type: "custom.write", data: %{text: text}}, _agent),
    do: Jido.Agent.Turn.new(JidoTest.Authoring.Agents.Fixtures.SetText, %{text: text})

  def handle_signal(signal, _agent),
    do: {:error, Jido.Error.routing_error("Unsupported custom Signal", target: signal.type)}
end

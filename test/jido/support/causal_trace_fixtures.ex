defmodule JidoTest.CausalTraceFixtures do
  @moduledoc false
  alias Jido.Examples.TurnObservation.EventProbe

  # The probe owner must outlive the peer RPC caller. Events are copied by the
  # same external handler used in the local example.
  def start_probe(ids) do
    Supervisor.start_child(Jido.Supervisor, %{
      id: make_ref(),
      restart: :temporary,
      start: {Elixir.Agent, :start_link, [fn -> EventProbe.attach(ids) end]}
    })
  end

  def events(probe) do
    Elixir.Agent.get(probe, fn value ->
      Enum.filter(EventProbe.events(value), &(Enum.take(&1.event, 2) == [:jido, :agent]))
    end)
  end
end

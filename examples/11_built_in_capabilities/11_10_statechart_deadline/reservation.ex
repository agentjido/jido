defmodule Jido.Examples.Statechart.Reservation do
  @moduledoc "Holds stock until checkout confirms the reservation or the deadline expires."

  use Jido.Statechart,
    chart: ~SCXML"""
    <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="held" datamodel="jido">
      <datamodel>
        <data id="hold_duration" expr="'30s'"/>
      </datamodel>
      <state id="held">
        <onentry>
          <send id="hold_deadline" event="examples.reservation.deadline" delayexpr="hold_duration"/>
        </onentry>
        <transition event="examples.reservation.confirm" target="confirmed">
          <cancel sendid="hold_deadline"/>
        </transition>
        <transition event="examples.reservation.deadline" target="expired"/>
      </state>
      <state id="confirmed"/>
      <final id="expired"/>
    </scxml>
    """

  def confirm(server) do
    signal = Jido.Signal.new!("examples.reservation.confirm", %{}, source: "/checkout")
    Jido.AgentServer.call(server, signal)
  end
end

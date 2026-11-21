defmodule Jido.Examples.Statechart.Approval do
  @moduledoc "Runs an order approval chart in a standalone Agent."

  use Jido.Statechart,
    chart: ~SCXML"""
    <scxml xmlns="http://www.w3.org/2005/07/scxml" version="1.0" initial="pending">
      <state id="pending">
        <transition event="examples.statechart.approval.approved" target="approved"/>
        <transition event="examples.statechart.approval.rejected" target="rejected"/>
      </state>
      <final id="approved"/>
      <final id="rejected"/>
    </scxml>
    """
end

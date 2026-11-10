defmodule Jido.Exec.System.Gaps.DeliveryRulesProbe do
  use ExUnit.Case, async: true
  @moduletag :system
  @moduletag :skip

  test "accepts one stable dispatch result and classifies equal and conflicting retries" do
    flunk("expected a public durable dispatch-result acceptance contract")
  end
end

Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.Redis do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :redis
  @moduletag persistence_profile: :redis
  @moduletag persistence_tier: :service
  use JidoTest.Persistence.Contracts.Store
  use JidoTest.Persistence.Contracts.Agent
  use JidoTest.Persistence.Contracts.Recovery
  use JidoTest.System.Scenarios.Checkpoints
  use JidoTest.System.Scenarios.Effects
  use JidoTest.System.Scenarios.Fencing
  use JidoTest.System.Scenarios.Recovery
  use JidoTest.System.Scenarios.Execution
  use JidoTest.System.Scenarios.Restoration
  use JidoTest.System.Scenarios.Overload
  use JidoTest.System.Scenarios.Topology
end

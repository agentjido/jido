Code.require_file("../support/case.exs", __DIR__)

defmodule JidoTest.System.Services.Bedrock do
  use JidoTest.System.Case, async: false
  @moduletag :service
  @moduletag adapter: :bedrock
  @moduletag persistence_profile: :bedrock
  @moduletag persistence_tier: :service
  @moduletag skip: "Bedrock service suite paused pending upstream fixes (bedrock-kv/bedrock#319)"
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

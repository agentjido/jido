defmodule Jido.Examples.DistributedAgents.FixedHome do
  @moduledoc "One named Jido instance that can run on either BEAM."

  use Jido, otp_app: :jido, namespace: "examples/distribution/native-fixed"

  @doc "Use the same home and generation on both peers."
  def options(home, persistence) do
    [cluster: [home: home, generation: "first-home", rpc_timeout: 2_000], persistence: persistence]
  end
end

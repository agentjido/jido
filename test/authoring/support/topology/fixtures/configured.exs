defmodule JidoTest.Authoring.Topology.Fixtures.Configured do
  use Jido.Topology, name: "authoring_configured"

  topology do
    agents do
      agent :parent, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :orphan, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :continued, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :stopped, JidoTest.Authoring.Topology.Fixtures.Worker
      agent :remote, JidoTest.Authoring.Topology.Fixtures.Worker, node: :"authoring@127.0.0.1"
    end

    resources do
      bus :events, config: [max_log_size: 17]
    end

    relationships do
      owns :parent, :orphan, on_parent_exit: :emit_orphan
      owns :parent, :continued, on_parent_exit: :continue
      owns :parent, :stopped, on_parent_exit: :stop
    end

    connections do
      subscribe :parent, to: :events, path: "authoring.work"
    end

    startup do
      concurrency 2
      max_agents 5
      retry_interval 37
      task_timeout 211
    end
  end
end

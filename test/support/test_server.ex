defmodule JidoTest.TestServer do
  defmodule BasicServer do
    @moduledoc "Basic agent with simple schema and actions"
    use Jido.Agent,
      name: "basic_agent",
      actions: [
        JidoTest.TestActions.BasicAction,
        JidoTest.TestActions.NoSchema,
        JidoTest.TestActions.EnqueueAction,
        JidoTest.TestActions.RegisterAction,
        JidoTest.TestActions.DeregisterAction
      ],
      schema: [
        location: [type: :atom, default: :home],
        battery_level: [type: :integer, default: 100]
      ]

    def start_link(opts \\ []) do
      agent_id = UUID.uuid4()
      agent = BasicServerAgent.new(agent_id)

      Jido.Agent.Server.start_link("test_#{agent_id}",
        name: "test_agent_server",
        agent: agent,
        schedule: [
          {"*/15 * * * *", fn -> System.cmd("rm", ["/tmp/tmp_"]) end}
        ],
        child_spec: [
          {BusSensor, %{name: "test_bus_sensor", bus: "test_bus"}}
        ]
      )
    end
  end
end

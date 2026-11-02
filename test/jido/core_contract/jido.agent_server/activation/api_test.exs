Code.require_file("../support.ex", __DIR__)

defmodule JidoTest.AgentServer.ActivationApiTest do
  use JidoTest.Case, async: false
  use Covenant.Case, component: "jido.agent_server.activation", async: false

  alias Jido.AgentServer, as: Server
  alias Jido.AgentServer.{RegistrationGuard, RegistryWorker}
  alias Jido.AgentServer.Supervisor, as: ServerSupervisor
  alias JidoTest.AgentServer.Fixtures, as: F

  setup do
    F.setup_runtime()
  end

  @tag obligation: "jido.agent_server.activation.I12"
  test "activation operations stay on the public AgentServer facade" do
    activation_api =
      MapSet.new([
        {:activation, 1},
        {:alive?, 1},
        {:await_ready, 2},
        {:child_spec, 1},
        {:start, 1},
        {:start_link, 1},
        {:whereis, 3},
        {:worker, 1}
      ])

    assert MapSet.subset?(activation_api, MapSet.new(documented_api(Server)))

    for module <- [ServerSupervisor, RegistrationGuard, RegistryWorker] do
      refute public_module?(module)
    end
  end

  @tag obligation: [
         "jido.agent_server.activation.I1",
         "jido.agent_server.activation.I4",
         "jido.agent_server.activation.I12"
       ]
  test "worker discovery is safe and lookup options are closed", c do
    id = "activation-api"
    {:ok, server} = Server.start(agent: %{c.agent | id: id}, jido: c.jido)
    root = Server.activation(server)

    assert Server.worker(root) == server
    assert Server.whereis(c.jido, id) == server
    assert Server.whereis(c.jido, id, unknown: true) == nil
    assert Server.whereis(c.jido, id, partition: nil, partition: nil) == nil

    assert :ok = Server.stop(server)
    assert Server.worker(root) == nil
    assert Server.worker(self()) == nil
  end

  defp documented_api(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    docs
    |> Enum.flat_map(fn
      {{kind, name, arity}, _, _, doc, _}
      when kind in [:function, :macro] and doc not in [:hidden, :none] ->
        [{name, arity}]

      _other ->
        []
    end)
    |> Enum.sort()
  end

  defp public_module?(module) do
    {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(module)
    module_doc not in [:hidden, :none]
  end
end

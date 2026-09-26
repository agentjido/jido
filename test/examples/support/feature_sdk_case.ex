defmodule JidoTest.FeatureSDKCase do
  @moduledoc "Public SDK setup and execution barriers for Runtime and Multi-agent examples."
  use ExUnit.CaseTemplate

  using do
    quote do
      use JidoTest.AgentCase
      import JidoTest.FeatureSDKCase
      alias Jido.AgentServer, as: Server
    end
  end

  def observed(module, key) do
    owner_key = System.unique_integer([:positive, :monotonic])
    :yes = :global.register_name({JidoTest.FeatureObserver, owner_key}, self())

    Jido.Agent.new!(
      Map.update(
        module.definition() |> Map.from_struct() |> Map.drop([:id, :state]),
        :plugins,
        [{JidoTest.FeatureObserver, [owner_key: owner_key, key: key]}],
        &(&1 ++ [{JidoTest.FeatureObserver, [owner_key: owner_key, key: key]}])
      )
    )
  end

  def state(server), do: Jido.AgentServer.snapshot(server).agent.state
end

defmodule JidoTest.FeatureObserver do
  @moduledoc false
  use Jido.Plugin, agent_server: JidoTest.FeatureObserver.Server
end

defmodule JidoTest.FeatureObserver.Server do
  @moduledoc false
  use Jido.AgentServer.Plugin

  alias Jido.AgentServer.Plugin.Admission

  def admit(_runtime_ref, %Admission{}, opts) do
    owner_key = Keyword.fetch!(opts, :owner_key)
    owner = :global.whereis_name({JidoTest.FeatureObserver, owner_key})
    key = Keyword.fetch!(opts, :key)

    observer = fn input ->
      send(owner, {:feature_work, self(), input})

      receive do
        :release -> :ok
        :fail -> raise "controlled worker failure"
      after
        5_000 -> raise "feature test barrier was not released"
      end
    end

    {:ok, %{key => observer}}
  end
end

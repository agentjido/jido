defmodule JidoTest.FeatureSDKCase do
  @moduledoc "Public SDK setup and execution barriers for Runtime and Multi-agent examples."
  use ExUnit.CaseTemplate

  using do
    quote do
      use JidoTest.AgentCase
      import JidoTest.FeatureSDKCase
      alias Jido.AgentServer, as: Server
      @moduletag :integration
    end
  end

  def observed(module, key) do
    module
    |> Jido.Agent.Builder.new()
    |> Jido.Agent.Builder.plugin(JidoTest.FeatureObserver, owner: self(), key: key)
    |> Jido.Agent.Builder.build!()
  end

  def state(server), do: Jido.AgentServer.snapshot(server).agent.state

  def barrier do
    owner = self()

    fn value ->
      send(owner, {:job_work, self(), value})

      receive do
        {:finish, result} -> result
      after
        5_000 -> raise "job test barrier was not released"
      end
    end
  end
end

defmodule JidoTest.FeatureObserver do
  @moduledoc false
  use Jido.Plugin

  def prepare(command, opts) do
    owner = Keyword.fetch!(opts, :owner)
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

    {:ok, %{command | context: Map.put(command.context, key, observer)}}
  end
end

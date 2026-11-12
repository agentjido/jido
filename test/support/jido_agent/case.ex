defmodule Jido.Test.Agent.Case do
  @moduledoc """
  Shared test case for opt-in agent examples.

  Each test gets an isolated Jido instance from `Jido.Test.Case`. The
  `:integration` tag keeps the suite out of the default test run. Use
  `mix test --only integration` or `mix test.examples` to run the suite.
  """

  use ExUnit.CaseTemplate

  alias Jido.AgentServer, as: Server

  using do
    quote do
      use Jido.Test.Case, async: false

      import Jido.Test.Agent.Case

      @moduletag :integration
    end
  end

  @type result :: %{
          agent: Jido.Agent.t(),
          server: GenServer.server(),
          state: map(),
          state_version: non_neg_integer()
        }

  @doc "Starts an example Elixir.Agent with a unique local ID."
  @spec start_agent!(module(), module(), keyword()) :: pid()
  def start_agent!(jido, agent, opts \\ []) when is_atom(jido) and is_atom(agent) do
    id = Keyword.get_lazy(opts, :id, fn -> unique_agent_id(agent) end)
    start_opts = Keyword.put(opts, :id, id)

    case Jido.Test.AgentServer.ExampleRuntime.start_agent(jido, agent, start_opts) do
      {:ok, server} -> server
      {:error, reason} -> raise "could not start #{inspect(agent)}: #{inspect(reason)}"
    end
  end

  @doc "Returns the committed Agent state and runtime version for assertions."
  @spec agent_result(GenServer.server()) :: result()
  def agent_result(server) do
    %{agent: agent, state_version: state_version} = Server.snapshot(server)

    %{
      agent: agent,
      server: server,
      state: agent.state,
      state_version: state_version
    }
  end

  defp unique_agent_id(agent) do
    name = agent |> Module.split() |> List.last() |> Macro.underscore()
    "example-#{name}-#{System.unique_integer([:positive])}"
  end
end

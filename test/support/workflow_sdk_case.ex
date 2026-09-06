defmodule JidoTest.WorkflowSDKCase do
  @moduledoc "Public SDK setup and timing controls for Workflow acceptance tests."
  use ExUnit.CaseTemplate

  using do
    quote do
      use JidoTest.Case, async: false
      import JidoTest.WorkflowSDKCase
      alias Jido.AgentServer, as: Server
      @moduletag :example

      @moduletag group: :workflow
      @moduletag complexity: 2
    end
  end

  def start_agent!(jido, agent, opts \\ []) do
    opts = Keyword.put_new(opts, :error_policy, fn _, _ -> :continue end)
    {:ok, server} = Jido.start_agent(jido, agent, opts)
    server
  end

  def context(barriers \\ [], extra \\ %{}) do
    observer = self()

    Map.put(extra, :on_step, fn stage, worker, value ->
      send(observer, {:step, stage, worker, value})

      if stage in barriers do
        receive do
          {:release, ^stage} -> :ok
        after
          5_000 -> raise "workflow test barrier was not released: #{inspect(stage)}"
        end
      end
    end)
  end

  def call_async(server, signal, context) do
    Task.async(fn -> Jido.AgentServer.call(server, signal, context: context) end)
  end

  def idle(server) do
    JidoTest.Eventually.eventually(fn -> Jido.AgentServer.status(server).phase == :idle end)
  end

  # Traverse the documented public error map, never private execution state.
  def errors(error) do
    error |> Jido.Flow.Error.to_map() |> flatten_errors()
  end

  defp flatten_errors(%{type: _, message: _} = error) do
    [error | flatten_errors(Map.get(error, :details, %{}))]
  end

  defp flatten_errors(map) when is_map(map),
    do: map |> Map.values() |> Enum.flat_map(&flatten_errors/1)

  defp flatten_errors(list) when is_list(list), do: Enum.flat_map(list, &flatten_errors/1)
  defp flatten_errors(_), do: []
end

defmodule JidoTest.WorkflowService do
  @moduledoc "Local adapter that records every call, including duplicate keys."
  use Elixir.Agent

  def start_link(responses),
    do: Elixir.Agent.start_link(fn -> %{responses: responses, calls: []} end)

  def call(server, operation, input) do
    Elixir.Agent.get_and_update(server, fn state ->
      response = Map.fetch!(state.responses, operation)
      {response, %{state | calls: state.calls ++ [{operation, input}]}}
    end)
  end

  def calls(server), do: Elixir.Agent.get(server, & &1.calls)
end

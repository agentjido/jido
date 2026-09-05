defmodule JidoTest.LLMSDKCase do
  @moduledoc "Real SDK tests with recorded external calls and worker barriers."
  alias Jido.AgentServer, as: Server
  use ExUnit.CaseTemplate

  using do
    quote do
      use JidoTest.Case, async: false

      import JidoTest.WorkflowSDKCase,
        only: [start_agent!: 2, start_agent!: 3, idle: 1, errors: 1]

      import JidoTest.LLMSDKCase
      alias Jido.AgentServer, as: Server
      alias JidoTest.LLMService, as: Service
      @moduletag :example
      @moduletag :integration
      @moduletag group: :llm
      @moduletag complexity: 3
    end
  end

  def service(responses) do
    {:ok, pid} =
      ExUnit.Callbacks.start_supervised({JidoTest.LLMService, responses}, id: make_ref())

    pid
  end

  def client(pid), do: {JidoTest.LLMService, pid}
  def calls(pid), do: JidoTest.LLMService.calls(pid)
  def state(server), do: Server.snapshot(server).agent.state

  def blocked(owner, key, response) do
    fn operation, input ->
      send(owner, {:provider_waiting, key, self(), operation, input})

      receive do
        {:release, ^key} -> response
      after
        5_000 -> raise "provider barrier not released: #{inspect(key)}"
      end
    end
  end
end

defmodule JidoTest.LLMService do
  @moduledoc false
  use Elixir.Agent
  @behaviour Jido.Examples.LLM.Adapter
  def start_link(responses),
    do: Elixir.Agent.start_link(fn -> %{responses: responses, calls: []} end)

  def call(pid, operation, input) do
    response =
      Elixir.Agent.get_and_update(pid, fn state ->
        {response, rest} =
          case state.responses do
            [next | rest] -> {next, rest}
            [] -> {{:error, :script_exhausted}, []}
          end

        {response, %{state | responses: rest, calls: state.calls ++ [{operation, input}]}}
      end)

    # Run barriers in the real caller worker, outside the recorder process.
    if is_function(response, 2), do: response.(operation, input), else: response
  end

  def calls(pid), do: Elixir.Agent.get(pid, & &1.calls)
end

defmodule JidoTest.Case do
  @moduledoc """
  Test case module that provides isolated Jido instances for testing.

  ## Usage

      defmodule MyTest do
        use JidoTest.Case, async: true
        
        test "my test", %{jido: jido} do
          {:ok, pid} = Jido.start_agent(jido, MyAgent)
          # ...
        end
      end

  Each test gets a unique Jido instance that is automatically started before
  the test and stopped after it completes. This ensures complete test isolation.

  ## Context

  The following keys are available in the test context:

  - `:jido` - The name of the Jido instance (atom)
  - `:jido_pid` - The PID of the Jido supervisor

  ## Helper Functions

  The module also provides helper functions:

  - `start_test_agent/2` - Starts an agent under the test's Jido instance
  - `test_registry/1` - Returns the registry name for the test's Jido instance
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoTest.Case

      @doc """
      Starts an agent under this test's Jido instance.
      """
      def start_test_agent(context, agent, opts \\ []) do
        Jido.start_agent(context.jido, agent, opts)
      end

      @doc """
      Returns the registry for this test's Jido instance.
      """
      def test_registry(context) do
        Jido.registry_name(context.jido)
      end

      @doc """
      Returns the task supervisor for this test's Jido instance.
      """
      def test_task_supervisor(context) do
        Jido.task_supervisor_name(context.jido)
      end

      @doc """
      Returns the agent supervisor for this test's Jido instance.
      """
      def test_agent_supervisor(context) do
        Jido.agent_supervisor_name(context.jido)
      end
    end
  end

  setup context do
    test_id = System.unique_integer([:positive])
    jido_name = :"jido_test_#{test_id}"

    {:ok, jido_pid} = Jido.start_link(name: jido_name)

    on_exit(fn ->
      if Process.alive?(jido_pid) do
        try do
          Supervisor.stop(jido_pid, :normal, 5_000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, Map.merge(context, %{jido: jido_name, jido_pid: jido_pid})}
  end
end

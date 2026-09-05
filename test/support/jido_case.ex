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
  the test and stopped before its cleanup callbacks run. This ensures complete
  test isolation, including persistence writes during shutdown.

  ## Context

  The following keys are available in the test context:

  - `:jido` - The name of the Jido instance (atom)
  - `:jido_pid` - The PID of the Jido supervisor

  ## Helper Functions

  The module also provides helper functions:

  - `test_registry/1` - Returns the registry name for the test's Jido instance
  - `unique_id/1` - Generates a unique ID with optional prefix
  - `signal/3` - Creates a test signal with sensible defaults
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoTest.Case
      import JidoTest.Eventually

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
      Returns the Agent supervisor for this test's Jido instance.
      """
      def test_agent_supervisor(context) do
        Jido.agent_supervisor_name(context.jido)
      end
    end
  end

  @doc """
  Generates a unique ID with an optional prefix.

  ## Examples

      unique_id()        # "test-<random suffix>"
      unique_id("agent") # "agent-<random suffix>"
  """
  def unique_id(prefix \\ "test") do
    suffix = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    "#{prefix}-#{suffix}"
  end

  @doc """
  Creates a test signal with sensible defaults.

  ## Examples

      signal("increment")
      signal("record", %{message: "hello"})
      signal("test", %{}, source: "/custom")
  """
  def signal(type, data \\ %{}, opts \\ []) do
    source = Keyword.get(opts, :source, "/test")
    Jido.Signal.new!(type, data, source: source)
  end

  setup context do
    test_id = System.unique_integer([:positive])
    jido_name = :"jido_test_#{test_id}"

    jido_pid = start_supervised!({Jido, name: jido_name})

    {:ok, Map.merge(context, %{jido: jido_name, jido_pid: jido_pid})}
  end
end

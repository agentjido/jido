defmodule JidoTest.BasicSDKCase do
  @moduledoc "Test support for the five Basic SDK integration fixtures."

  use ExUnit.CaseTemplate

  using do
    quote do
      use JidoTest.Case, async: false
      import JidoTest.BasicSDKCase

      @moduletag :example

      @moduletag group: :basic
      @moduletag complexity: 1
    end
  end

  def start_agent!(jido, agent, opts \\ []) do
    opts = Keyword.put_new_lazy(opts, :id, &JidoTest.Case.unique_id/0)
    {:ok, server} = Jido.start_agent(jido, agent, opts)
    server
  end

  # Error observation uses the public Server policy callback. It does not
  # replace execution or inspect private Server state.
  def observe_errors do
    observer = self()

    fn reason, outcome ->
      send(observer, {:sdk_error, reason, outcome})
      :continue
    end
  end

  def await_idle(server) do
    JidoTest.Eventually.eventually(fn ->
      Jido.AgentServer.status(server).phase == :idle
    end)
  end
end

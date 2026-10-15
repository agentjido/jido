defmodule Jido.AgentServer.Execution.Store do
  @moduledoc false
  @behaviour Runic.Runner.Store

  # Turn execution lives in its Worker. Agent persistence owns committed state.
  @impl true
  def init_store(_opts), do: {:ok, nil}

  @impl true
  def save(_id, _log, _state), do: :ok

  @impl true
  def load(_id, _state), do: {:error, :not_found}

  @impl true
  def list(_state), do: {:ok, []}

  @impl true
  def exists?(_id, _state), do: false
end

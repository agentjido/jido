defmodule JidoTest.Agent.UnloadedCodecExtension do
  @moduledoc false

  @behaviour Jido.Agent.Extension

  @impl true
  def decode(_document, _registry) do
    {:error, Jido.Error.validation_error("unloaded extension decoder was called")}
  end
end

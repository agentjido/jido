defmodule Jido.AgentServer.Shutdown do
  @moduledoc false

  @spec normalize_reason(term()) :: term()
  def normalize_reason(:normal), do: :normal
  def normalize_reason(:shutdown), do: :shutdown
  def normalize_reason({:shutdown, _reason} = reason), do: reason
  def normalize_reason(reason), do: {:shutdown, reason}

  def clean?(:normal), do: true
  def clean?(:shutdown), do: true
  def clean?({:shutdown, _reason}), do: true
  def clean?(_reason), do: false
end

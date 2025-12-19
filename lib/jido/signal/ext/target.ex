defmodule Jido.Signal.Ext.Target do
  @moduledoc """
  Target extension for Jido Signals.

  Provides a simple extension to handle the "target" field commonly used in
  Jido signals for routing and delivery purposes. The target typically specifies
  the intended recipient or destination of a signal.

  ## Usage

  The target extension handles a single string field that identifies the target:

      # In signal creation
      {:ok, signal} = Jido.Signal.new("user.created", %{user_id: "123"}, 
        target: "agent-456"
      )

      # Accessing target data
      target_id = signal.extensions["target"]

  ## CloudEvents Serialization

  The target is serialized as a top-level CloudEvents attribute named "target":

      {
        "specversion": "1.0.2",
        "type": "user.created",
        "source": "/users",
        "target": "agent-456",
        ...
      }
  """

  use Jido.Signal.Ext,
    namespace: "target",
    schema: [
      target: [type: :string, required: true, doc: "Target identifier for signal routing"]
    ]

  @impl true
  def to_attrs(%{target: target}) do
    %{"target" => target}
  end

  @impl true
  def from_attrs(attrs) do
    case Map.get(attrs, "target") do
      nil -> nil
      target when is_binary(target) -> %{target: target}
      target -> %{target: to_string(target)}
    end
  end
end

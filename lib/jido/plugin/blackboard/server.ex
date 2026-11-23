defmodule Jido.Plugin.Blackboard.Server do
  @moduledoc """
  Starts a named in-memory board under its owning Agent's activation.

      plugins: [{Jido.Plugin.Blackboard.Server, %{name: "inventory", initial: %{"bin-a" => 0}}}]

  The owning Agent needs a local Jido instance. A new board process starts
  from the configured values and creates a new revision.
  """

  use Jido.Plugin, option_keys: [agent_server: [:name, :initial]]

  alias Jido.Blackboard
  alias Jido.Plugin.Init

  @impl true
  def validate_options(opts) do
    case Keyword.get(opts, :name) do
      name when is_binary(name) and byte_size(name) > 0 ->
        Blackboard.validate_changes(Keyword.get(opts, :initial, %{}), [])

      _name ->
        {:error, :invalid_board_name}
    end
  end

  @impl true
  def child_spec(%Init{jido: instance, options: opts, module: module}) do
    args = {instance, Keyword.fetch!(opts, :name), Keyword.get(opts, :initial, %{})}
    Supervisor.child_spec({Blackboard.Server, args}, id: module)
  end
end

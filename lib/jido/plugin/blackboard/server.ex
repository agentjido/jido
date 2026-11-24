defmodule Jido.Plugin.Blackboard.Server do
  @moduledoc """
  Starts a named board under its owning Agent's activation.

      plugins: [{Jido.Plugin.Blackboard.Server, %{name: "inventory", initial: %{"bin-a" => 0}}}]

  Set `:persistence` to `:inherit` to use the instance's Store and codec.
  The board uses the owner's stable Agent Address and its own name as its
  storage identity. A new process restores saved values, or uses the initial
  values on first start. Each process issues a fresh revision.
  """

  use Jido.Plugin, option_keys: [agent_server: [:name, :initial, :persistence]]

  alias Jido.Blackboard
  alias Jido.Plugin.Init

  @impl true
  def validate_options(opts) do
    with name when is_binary(name) and byte_size(name) > 0 <- opts[:name] do
      if Keyword.get(opts, :persistence, false) in [false, :inherit] do
        Blackboard.validate_changes(Keyword.get(opts, :initial, %{}), [])
      else
        {:error, :invalid_board_persistence}
      end
    else
      _invalid -> {:error, :invalid_board_name}
    end
  end

  @impl true
  def child_spec(%Init{module: module} = init),
    do: Supervisor.child_spec({Blackboard.Server, init}, id: module)
end

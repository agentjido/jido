defmodule Jido.AgentServer.State.Lifecycle do
  @moduledoc """
  Lifecycle state for pool-managed agents.

  Tracks attachment, idle timeout, and storage configuration
  for agents managed by Jido.Agent.InstanceManager.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              mod:
                Zoi.atom(description: "Lifecycle module")
                |> Zoi.default(Jido.AgentServer.Lifecycle.Noop),
              pool:
                Zoi.atom(description: "Pool name if started via InstanceManager")
                |> Zoi.optional(),
              pool_key:
                Zoi.any(description: "Pool key if started via InstanceManager") |> Zoi.optional(),
              idle_timeout:
                Zoi.any(description: "Idle timeout in ms (:infinity to disable)")
                |> Zoi.default(:infinity),
              storage: Zoi.any(description: "Storage config") |> Zoi.optional(),
              attachments:
                Zoi.any(description: "MapSet of attached owner pids")
                |> Zoi.default(MapSet.new()),
              attachment_monitors:
                Zoi.map(description: "Map of monitor_ref => owner_pid") |> Zoi.default(%{}),
              idle_timer: Zoi.any(description: "Timer ref for idle timeout") |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc """
  Creates a new Lifecycle state from options.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) do
    attrs = %{
      mod: Keyword.get(opts, :lifecycle_mod, Jido.AgentServer.Lifecycle.Noop),
      pool: Keyword.get(opts, :pool),
      pool_key: Keyword.get(opts, :pool_key),
      idle_timeout: Keyword.get(opts, :idle_timeout, :infinity),
      storage: Keyword.get(opts, :storage),
      attachments: MapSet.new(),
      attachment_monitors: %{},
      idle_timer: nil
    }

    Zoi.parse(@schema, attrs)
  end

  @doc """
  Clears the active idle timer reference.
  """
  @spec clear_idle_timer(t()) :: t()
  def clear_idle_timer(%__MODULE__{} = lifecycle) do
    %{lifecycle | idle_timer: nil}
  end
end

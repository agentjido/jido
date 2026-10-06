defmodule Jido.AgentServer.State do
  @moduledoc false

  alias Jido.AgentServer.Options

  @schema Zoi.struct(
            __MODULE__,
            %{
              config: Options.runtime_schema(),
              agent: Zoi.any(description: "Live immutable Agent value"),
              plugin_specs: Zoi.list(Zoi.any(), description: "Validated Agent Plugin specs"),
              jido: Zoi.any(description: "Owning Jido instance") |> Zoi.optional(),
              agent_namespace:
                Zoi.string(description: "Cached public Agent namespace")
                |> Zoi.optional(),
              partition: Zoi.any(description: "Logical Agent partition") |> Zoi.optional(),
              registry: Zoi.any(description: "Jido instance Registry") |> Zoi.optional(),
              registered?:
                Zoi.boolean(description: "Whether the Agent is Registry named")
                |> Zoi.default(false),
              postponed_tokens: Zoi.any(description: "Bounded postponed Signal token set"),
              error_count:
                Zoi.integer(description: "Consecutive runtime error count") |> Zoi.default(0),
              parent: Zoi.any(description: "Current logical parent") |> Zoi.optional(),
              children:
                Zoi.map(description: "Tracked Agent and Plugin children") |> Zoi.default(%{}),
              child_spawn_requests:
                Zoi.map(description: "Child creation identities, including unresolved starts")
                |> Zoi.default(%{}),
              initial_persistence:
                Zoi.enum([:none, :create, :restored, :definition_upgrade, :ready],
                  description: "Initial durable-record state"
                )
                |> Zoi.default(:none),
              attachments:
                Zoi.map(description: "Attached owner PIDs and monitor references")
                |> Zoi.default(%{}),
              idle_timer: Zoi.any(description: "Current idle timer") |> Zoi.optional(),
              debug:
                Zoi.boolean(description: "Enable the Agent event buffer") |> Zoi.default(false),
              debug_events:
                Zoi.list(Zoi.any(), description: "Recent Agent runtime events") |> Zoi.default([]),
              state_version: Zoi.integer(description: "Agent commit revision"),
              checkpoint_origin_module:
                Zoi.atom(description: "Definition module used to start this Agent")
                |> Zoi.optional(),
              activation_id:
                Zoi.string(description: "Telemetry activation identity") |> Zoi.optional(),
              activation_span:
                Zoi.any(description: "Activation telemetry span") |> Zoi.optional(),
              active: Zoi.any(description: "Active Turn lifecycle record"),
              plugin_bootstrap:
                Zoi.any(description: "Active Plugin readiness check") |> Zoi.optional(),
              startup_reply:
                Zoi.any(description: "Temporary supervised startup reply address")
                |> Zoi.optional(),
              admission_task:
                Zoi.any(description: "Active Plugin admission task") |> Zoi.optional(),
              commit_task:
                Zoi.any(description: "Active Plugin commit notification task") |> Zoi.optional(),
              directive_task:
                Zoi.any(description: "Active Plugin Directive task") |> Zoi.optional(),
              child_task:
                Zoi.any(description: "Owned child lifecycle operation") |> Zoi.optional(),
              error_policy_tasks:
                Zoi.map(description: "Bounded asynchronous error Signal deliveries")
                |> Zoi.default(%{})
            }
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  def add_child(%__MODULE__{} = state, key, child) do
    %{state | children: Map.put(state.children, key, child)}
  end

  @doc false
  def remove_child(%__MODULE__{} = state, key) do
    %{state | children: Map.delete(state.children, key)}
  end

  @doc false
  def child(%__MODULE__{} = state, key), do: Map.get(state.children, key)

  @doc false
  def child_by_ref(%__MODULE__{} = state, ref) do
    Enum.find(state.children, fn {_key, child} -> child.ref == ref end)
  end

  @doc false
  def mark_spawn_active(%__MODULE__{} = state, tag) do
    case Map.fetch(state.child_spawn_requests, tag) do
      {:ok, request} ->
        requests = Map.put(state.child_spawn_requests, tag, %{request | status: :active})
        %{state | child_spawn_requests: requests}

      :error ->
        state
    end
  end
end

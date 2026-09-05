defmodule Jido.AgentServer.State do
  @moduledoc false

  @schema Zoi.struct(
            __MODULE__,
            %{
              agent: Zoi.any(description: "Live immutable Agent value"),
              plugin_specs: Zoi.list(Zoi.any(), description: "Validated Agent Plugin specs"),
              jido: Zoi.any(description: "Owning Jido instance") |> Zoi.optional(),
              partition: Zoi.any(description: "Logical Agent partition") |> Zoi.optional(),
              registry: Zoi.any(description: "Jido instance Registry") |> Zoi.optional(),
              registered?:
                Zoi.boolean(description: "Whether the Agent is Registry named")
                |> Zoi.default(false),
              exec_module: Zoi.atom(description: "Executable runtime module"),
              exec_opts: Zoi.any(description: "Executable runtime options"),
              max_postponed_signals: Zoi.any(description: "Postponed Signal admission limit"),
              postponed_tokens: Zoi.any(description: "Bounded postponed Signal token set"),
              max_directives_per_turn: Zoi.any(description: "Directive batch limit"),
              directive_timeout: Zoi.any(description: "Plugin and external Directive timeout"),
              default_dispatch:
                Zoi.any(description: "Default outbound Signal dispatch") |> Zoi.optional(),
              error_policy:
                Zoi.any(description: "Agent Server error policy") |> Zoi.default(:log_only),
              error_count:
                Zoi.integer(description: "Consecutive runtime error count") |> Zoi.default(0),
              parent: Zoi.any(description: "Current logical parent") |> Zoi.optional(),
              orphaned_from: Zoi.any(description: "Former logical parent") |> Zoi.optional(),
              children:
                Zoi.map(description: "Tracked Agent and Plugin children") |> Zoi.default(%{}),
              child_spawn_requests:
                Zoi.map(
                  description: "Remote child creation identities, including unresolved starts"
                )
                |> Zoi.default(%{}),
              on_parent_death: Zoi.atom(description: "Parent death policy") |> Zoi.default(:stop),
              pool: Zoi.atom(description: "Owning Agent InstanceManager") |> Zoi.optional(),
              pool_key: Zoi.any(description: "Agent InstanceManager key") |> Zoi.optional(),
              idle_timeout:
                Zoi.any(description: "Idle timeout in milliseconds") |> Zoi.default(:infinity),
              persistence:
                Zoi.any(description: "Optional Agent persistence adapter") |> Zoi.optional(),
              attachments:
                Zoi.any(description: "Attached owner process set") |> Zoi.default(MapSet.new()),
              attachment_monitors:
                Zoi.map(description: "Attachment monitor references") |> Zoi.default(%{}),
              idle_timer: Zoi.any(description: "Current idle timer") |> Zoi.optional(),
              spawn_fun:
                Zoi.any(description: "Optional process spawn function") |> Zoi.optional(),
              debug:
                Zoi.boolean(description: "Enable the Agent event buffer") |> Zoi.default(false),
              debug_events:
                Zoi.list(Zoi.any(), description: "Recent Agent runtime events") |> Zoi.default([]),
              debug_max_events:
                Zoi.integer(description: "Maximum recent runtime events") |> Zoi.default(500),
              state_version: Zoi.integer(description: "Agent commit revision"),
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
              directive_task:
                Zoi.any(description: "Active Plugin Directive task") |> Zoi.optional()
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
end

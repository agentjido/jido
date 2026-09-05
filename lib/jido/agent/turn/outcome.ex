defmodule Jido.Agent.Turn.Outcome do
  @moduledoc """
  The terminal runtime outcome for one admitted Agent Turn.

  An Outcome records whether the Agent committed, where processing stopped,
  and whether post-commit Directives completed. It contains no process handles
  or private Agent Server state.
  """

  alias Jido.Error
  alias Jido.Signal.ID

  @statuses [:succeeded, :failed, :cancelled, :timed_out, :indeterminate]
  @stages [:prepare, :execute, :finalize, :commit, :directive]

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Stable Turn identifier"),
              agent_id: Zoi.string(description: "Owning Agent identifier"),
              source_signal:
                Zoi.struct(Jido.Signal, description: "Signal received by the Server"),
              effective_signal:
                Zoi.struct(Jido.Signal, description: "Signal after Plugin preparation")
                |> Zoi.optional(),
              status: Zoi.enum(@statuses, description: "Terminal Turn status"),
              stage: Zoi.enum(@stages, description: "Stage where the Turn stopped"),
              committed?: Zoi.boolean(description: "Whether Agent state committed"),
              state_version_before:
                Zoi.integer(description: "Agent state version before the Turn") |> Zoi.min(0),
              state_version_after:
                Zoi.integer(description: "Committed Agent state version")
                |> Zoi.min(0)
                |> Zoi.optional(),
              error: Zoi.any(description: "Terminal error") |> Zoi.optional(),
              directives:
                Zoi.map(
                  %{
                    total: Zoi.integer() |> Zoi.min(0),
                    completed: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0),
                    failed: Zoi.integer() |> Zoi.min(0),
                    failed_index:
                      Zoi.integer() |> Zoi.min(0) |> Zoi.nullable() |> Zoi.default(nil),
                    skipped: Zoi.integer() |> Zoi.min(0) |> Zoi.default(0)
                  },
                  description: "Directive completion summary"
                )
                |> Zoi.default(%{
                  total: 0,
                  completed: 0,
                  failed: 0,
                  failed_index: nil,
                  skipped: 0
                }),
              started_at:
                Zoi.integer(description: "Turn start time in Unix milliseconds") |> Zoi.min(0),
              finished_at:
                Zoi.integer(description: "Turn finish time in Unix milliseconds") |> Zoi.min(0),
              duration_ms: Zoi.integer(description: "Turn duration in milliseconds") |> Zoi.min(0)
            },
            coerce: true,
            empty_values: [nil]
          )

  @type status :: :succeeded | :failed | :cancelled | :timed_out | :indeterminate
  @type stage :: :prepare | :execute | :finalize | :commit | :directive
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a Turn outcome."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one validated Turn outcome."
  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    with {:ok, outcome} <- Zoi.parse(@schema, attrs),
         :ok <- validate_id(outcome.id),
         :ok <- validate_commit(outcome),
         :ok <- validate_status(outcome),
         :ok <- validate_stage(outcome),
         :ok <- validate_timing(outcome),
         :ok <- validate_directives(outcome.directives) do
      {:ok, outcome}
    end
  end

  def new(value), do: invalid("Turn Outcome must be a map", %{value: value})

  @doc "Creates one validated Turn outcome or raises."
  @spec new!(map() | keyword()) :: t() | no_return()
  def new!(attrs) do
    case new(attrs) do
      {:ok, outcome} -> outcome
      {:error, error} -> raise error
    end
  end

  defp validate_id(id) do
    if ID.valid?(id),
      do: :ok,
      else: invalid("Turn Outcome id must be a UUID7", %{id: id})
  end

  defp validate_commit(%__MODULE__{
         committed?: true,
         state_version_before: before,
         state_version_after: after_version
       })
       when after_version == before + 1,
       do: :ok

  defp validate_commit(%__MODULE__{committed?: false, state_version_after: nil}), do: :ok

  defp validate_commit(outcome) do
    invalid("Turn Outcome commit fields are inconsistent", %{
      committed?: outcome.committed?,
      state_version_after: outcome.state_version_after
    })
  end

  defp validate_status(%__MODULE__{status: :succeeded, error: nil}), do: :ok

  defp validate_status(%__MODULE__{status: status, error: error})
       when status != :succeeded and not is_nil(error), do: :ok

  defp validate_status(outcome) do
    invalid("Turn Outcome status and error are inconsistent", %{
      status: outcome.status,
      error: outcome.error
    })
  end

  defp validate_stage(%__MODULE__{stage: :directive, committed?: true}), do: :ok

  defp validate_stage(%__MODULE__{status: :succeeded, stage: stage, committed?: true})
       when stage in [:commit, :directive],
       do: :ok

  defp validate_stage(%__MODULE__{status: status, stage: stage, committed?: false})
       when status != :succeeded and stage in [:prepare, :execute, :finalize, :commit],
       do: :ok

  defp validate_stage(outcome) do
    invalid("Turn Outcome stage is inconsistent", %{
      status: outcome.status,
      stage: outcome.stage,
      committed?: outcome.committed?
    })
  end

  defp validate_timing(%__MODULE__{started_at: started_at, finished_at: finished_at})
       when finished_at >= started_at,
       do: :ok

  defp validate_timing(outcome) do
    invalid("Turn Outcome timing is inconsistent", %{
      started_at: outcome.started_at,
      finished_at: outcome.finished_at
    })
  end

  defp validate_directives(%{
         total: total,
         completed: completed,
         failed: failed,
         failed_index: failed_index,
         skipped: skipped
       })
       when completed + failed + skipped == total and failed in 0..1 do
    case {failed, failed_index} do
      {0, nil} ->
        :ok

      {1, ^completed} ->
        :ok

      _other ->
        invalid("Turn Outcome Directive failure position is invalid", %{
          failed_index: failed_index
        })
    end
  end

  defp validate_directives(directives) do
    invalid("Turn Outcome Directive summary is invalid", %{directives: directives})
  end

  defp invalid(message, details) do
    {:error, Error.validation_error(message, kind: :config, details: details)}
  end
end

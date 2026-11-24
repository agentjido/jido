defmodule Jido.Durable.Continuation do
  @moduledoc false

  alias Jido.Flow.Identity

  @type id :: String.t()
  @type status :: :running | :accepted | :released | :completed | :failed | :cancelled

  @type direct :: %{
          optional(:result_handoff) => true,
          id: id(),
          signal: Jido.Signal.t(),
          admitted_signal: Jido.Signal.t(),
          context: map(),
          plugin_inputs: map(),
          fingerprint: String.t(),
          status: :running | :completed | :failed | :cancelled,
          expires_at: non_neg_integer() | :infinity
        }

  @type resume_receipt :: %{
          input: Jido.Exec.Wait.input(),
          result: Jido.AgentServer.TurnResult.t() | nil
        }

  @type terminal_receipt :: %{
          id: id(),
          status: :completed | :failed | :cancelled,
          terminal_result: Jido.AgentServer.TurnResult.t(),
          completed_at: non_neg_integer()
        }

  @type settled_flow :: %{
          optional(:resume) => resume_receipt(),
          optional(:terminal_result) => Jido.AgentServer.TurnResult.t(),
          optional(:completed_at) => non_neg_integer(),
          id: id(),
          status: :completed | :failed | :cancelled,
          expires_at: non_neg_integer() | :infinity
        }

  @type accepted_handoff :: %{
          optional(:result_handoff) => true,
          id: id(),
          signal: Jido.Signal.t(),
          context: map(),
          fingerprint: String.t(),
          status: :accepted | :failed | :cancelled,
          instruction: Jido.Instruction.t(),
          chain_id: id(),
          chain_order: pos_integer(),
          predecessor_id: id()
        }

  @type released_handoff :: %{
          optional(:result_handoff) => true,
          id: id(),
          signal: Jido.Signal.t(),
          admitted_signal: Jido.Signal.t(),
          context: map(),
          plugin_inputs: map(),
          fingerprint: String.t(),
          status: :released | :completed | :failed | :cancelled,
          expires_at: non_neg_integer() | :infinity,
          instruction: Jido.Instruction.t(),
          chain_id: id(),
          chain_order: pos_integer(),
          predecessor_id: id()
        }

  @type t :: direct() | accepted_handoff() | released_handoff() | terminal_receipt() | settled_flow()

  @doc false
  @spec running(map()) :: {:ok, direct()} | {:error, term()}
  def running(
        %{
          id: id,
          signal: %Jido.Signal{} = signal,
          admitted_signal: %Jido.Signal{} = admitted_signal,
          context: context,
          plugin_inputs: plugin_inputs,
          target: target,
          expires_at: expires_at
        } = attrs
      ) do
    continuation =
      %{
        id: id,
        signal: signal,
        admitted_signal: admitted_signal,
        context: context,
        plugin_inputs: plugin_inputs,
        fingerprint: Identity.executable_digest(target),
        status: :running,
        expires_at: expires_at
      }
      |> maybe_put_result_handoff(Map.get(attrs, :result_handoff, false))

    with :ok <- validate(continuation),
         :ok <- portable(continuation),
         do: {:ok, continuation}
  end

  def running(_attrs), do: invalid()

  @doc false
  @spec accept_handoff(map()) :: {:ok, accepted_handoff()} | {:error, term()}
  def accept_handoff(
        %{
          id: id,
          signal: %Jido.Signal{} = signal,
          context: context,
          instruction: %Jido.Instruction{} = instruction,
          chain_id: chain_id,
          chain_order: chain_order,
          predecessor_id: predecessor_id
        } = attrs
      ) do
    continuation =
      %{
        id: id,
        signal: signal,
        context: context,
        fingerprint: instruction_fingerprint(instruction),
        status: :accepted,
        instruction: instruction,
        chain_id: chain_id,
        chain_order: chain_order,
        predecessor_id: predecessor_id
      }
      |> maybe_put_result_handoff(Map.get(attrs, :result_handoff, false))

    with :ok <- validate(continuation), do: {:ok, continuation}
  end

  def accept_handoff(_attrs), do: invalid()

  @doc false
  @spec release_handoff(accepted_handoff(), map()) ::
          {:ok, released_handoff()} | {:error, term()}
  def release_handoff(%{status: :accepted} = continuation, %{
        admitted_signal: %Jido.Signal{} = signal,
        plugin_inputs: plugin_inputs,
        expires_at: expires_at
      }) do
    released =
      Map.merge(continuation, %{
        status: :released,
        admitted_signal: signal,
        plugin_inputs: plugin_inputs,
        expires_at: expires_at
      })

    with :ok <- validate(released), do: {:ok, released}
  end

  def release_handoff(_continuation, _attrs), do: invalid()

  @doc false
  @spec put_status!(t(), status()) :: t()
  def put_status!(%{expires_at: _} = continuation, status)
      when status in [:completed, :failed, :cancelled] and not is_map_key(continuation, :instruction) do
    updated =
      continuation
      |> Map.take([:id, :expires_at, :resume, :terminal_result, :completed_at])
      |> Map.put(:status, status)

    :ok = validate(updated)
    updated
  end

  def put_status!(continuation, status) do
    updated = %{continuation | status: status}
    :ok = validate(updated)
    updated
  end

  @doc false
  @spec put_resume_input!(map(), Jido.Exec.Wait.input()) :: map()
  def put_resume_input!(continuation, input) do
    updated = Map.put(continuation, :resume, %{input: input, result: nil})
    :ok = validate(updated)
    updated
  end

  @doc false
  @spec put_resume_result!(map(), Jido.AgentServer.TurnResult.t()) :: map()
  def put_resume_result!(%{resume: resume} = continuation, result) do
    updated = %{continuation | resume: %{resume | result: result}}
    :ok = validate(updated)
    updated
  end

  @doc false
  @spec retain_result!(t() | nil, Jido.AgentServer.TurnResult.t()) :: t()
  def retain_result!(continuation, %Jido.AgentServer.TurnResult{} = result) do
    completed_at = result.completed_at

    updated =
      case continuation do
        nil ->
          %{
            id: result.turn_id,
            status: receipt_status(result.status),
            terminal_result: result,
            completed_at: completed_at
          }

        %{} ->
          continuation
          |> Map.put(:terminal_result, result)
          |> Map.put(:completed_at, completed_at)
      end

    :ok = validate(updated)
    :ok = portable(updated)
    updated
  end

  @doc false
  @spec terminal_result(t() | nil) :: {:ok, Jido.AgentServer.TurnResult.t()} | :error
  def terminal_result(%{terminal_result: %Jido.AgentServer.TurnResult{} = result}),
    do: {:ok, result}

  def terminal_result(_continuation), do: :error

  @doc false
  @spec acknowledge_result(t() | nil, id()) ::
          {:ok, t() | nil, boolean()} | {:error, :turn_result_mismatch}
  def acknowledge_result(%{terminal_result: %{turn_id: turn_id}} = continuation, turn_id) do
    cleared = Map.drop(continuation, [:terminal_result, :completed_at])
    cleared = if map_size(cleared) == 2, do: nil, else: cleared
    if cleared, do: :ok = validate(cleared)
    {:ok, cleared, true}
  end

  def acknowledge_result(%{terminal_result: %Jido.AgentServer.TurnResult{}}, _turn_id),
    do: {:error, :turn_result_mismatch}

  def acknowledge_result(continuation, _turn_id), do: {:ok, continuation, false}

  @doc false
  @spec retry(t() | nil, Jido.Signal.t()) ::
          :new | {:completed, id()} | {:ok, Jido.AgentServer.TurnResult.t()} | {:error, atom()}
  def retry(%{resume: %{input: stored, result: result}}, %Jido.Signal{} = signal) do
    cond do
      stored.id != signal.id ->
        :new

      true ->
        with {:ok, input} <- Jido.Exec.Wait.input(stored.wait_id, signal) do
          cond do
            input != stored -> {:error, :conflicting_input_id}
            is_nil(result) -> {:error, :resume_in_progress}
            true -> {:ok, result}
          end
        end
    end
  end

  def retry(
        %{id: turn_id, status: :completed},
        %Jido.Signal{
          type: "jido.durable.wake",
          data: %{turn_id: turn_id, wait_id: wait_id, deadline: deadline}
        }
      )
      when is_binary(wait_id) and is_integer(deadline),
      do: {:completed, turn_id}

  def retry(_continuation, %Jido.Signal{}), do: :new

  @doc false
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(%{id: id, status: status, expires_at: expires_at} = continuation)
      when status in [:completed, :failed, :cancelled] and map_size(continuation) in 3..6 and
             (expires_at == :infinity or (is_integer(expires_at) and expires_at >= 0)) do
    if valid_id?(id) and valid_keys?(continuation, [:id, :status, :expires_at]) and
         not Map.has_key?(continuation, :result_handoff) and valid_resume?(continuation) and
         valid_terminal_result?(continuation),
       do: :ok,
       else: invalid()
  end

  def validate(
        %{
          id: id,
          status: status,
          terminal_result: %Jido.AgentServer.TurnResult{} = result,
          completed_at: completed_at
        } = continuation
      )
      when status in [:completed, :failed, :cancelled] and map_size(continuation) == 4 do
    if valid_id?(id) and result.turn_id == id and valid_terminal?(result, completed_at),
      do: :ok,
      else: invalid()
  end

  def validate(
        %{
          id: id,
          status: status,
          signal: %Jido.Signal{},
          context: context,
          fingerprint: fingerprint,
          instruction: %Jido.Instruction{},
          chain_id: chain_id,
          chain_order: chain_order,
          predecessor_id: predecessor_id
        } = continuation
      )
      when status in [:accepted, :failed, :cancelled] and is_map(context) and
             is_binary(fingerprint) and is_integer(chain_order) and chain_order > 0 and
             map_size(continuation) in 9..13 and
             not is_map_key(continuation, :admitted_signal) do
    if valid_keys?(continuation, [
         :id,
         :status,
         :signal,
         :context,
         :fingerprint,
         :instruction,
         :chain_id,
         :chain_order,
         :predecessor_id
       ]) and valid_id?(id) and valid_id?(chain_id) and valid_id?(predecessor_id) and
         valid_optional_fields?(continuation),
       do: :ok,
       else: invalid()
  end

  def validate(
        %{
          id: id,
          status: status,
          signal: %Jido.Signal{},
          admitted_signal: %Jido.Signal{},
          context: context,
          plugin_inputs: plugin_inputs,
          fingerprint: fingerprint,
          expires_at: expires_at
        } = continuation
      )
      when status in [:running, :completed, :failed, :cancelled] and is_map(context) and
             is_map(plugin_inputs) and is_binary(fingerprint) and
             (expires_at == :infinity or (is_integer(expires_at) and expires_at >= 0)) and
             map_size(continuation) in 8..12 and
             not is_map_key(continuation, :instruction) do
    if valid_keys?(continuation, [
         :id,
         :status,
         :signal,
         :admitted_signal,
         :context,
         :plugin_inputs,
         :fingerprint,
         :expires_at
       ]) and valid_id?(id) and valid_optional_fields?(continuation),
       do: :ok,
       else: invalid()
  end

  def validate(
        %{
          id: id,
          status: status,
          signal: %Jido.Signal{},
          admitted_signal: %Jido.Signal{},
          context: context,
          plugin_inputs: plugin_inputs,
          fingerprint: fingerprint,
          expires_at: expires_at,
          instruction: %Jido.Instruction{},
          chain_id: chain_id,
          chain_order: chain_order,
          predecessor_id: predecessor_id
        } = continuation
      )
      when status in [:released, :completed, :failed, :cancelled] and is_map(context) and
             is_map(plugin_inputs) and is_binary(fingerprint) and
             (expires_at == :infinity or (is_integer(expires_at) and expires_at >= 0)) and
             is_integer(chain_order) and chain_order > 0 and map_size(continuation) in 12..16 do
    if valid_keys?(continuation, [
         :id,
         :status,
         :signal,
         :admitted_signal,
         :context,
         :plugin_inputs,
         :fingerprint,
         :expires_at,
         :instruction,
         :chain_id,
         :chain_order,
         :predecessor_id
       ]) and valid_id?(id) and valid_id?(chain_id) and valid_id?(predecessor_id) and
         valid_optional_fields?(continuation),
       do: :ok,
       else: invalid()
  end

  def validate(_continuation), do: invalid()

  @doc false
  @spec portable(t()) :: :ok | {:error, Jido.Error.ValidationError.t()}
  def portable(continuation) do
    with {:error, path} <- Jido.Codec.Term.validate(continuation, :continuation) do
      Jido.Error.validation_result(
        :non_portable_term,
        path,
        "Durable Turn #{non_portable_subject(path)} is not portable. Stored data cannot hold " <>
          "PIDs, ports, references, functions, improper lists, or partial bitstrings."
      )
    end
  end

  @doc false
  @spec compatible(t(), Jido.Instruction.t()) :: :ok | {:error, :execution_definition_changed}
  def compatible(%{fingerprint: fingerprint}, %Jido.Instruction{} = instruction) do
    if instruction_fingerprint(instruction) == fingerprint,
      do: :ok,
      else: {:error, :execution_definition_changed}
  end

  defp non_portable_subject([:continuation, :context, key | _path]),
    do: "context key #{inspect(key)}"

  defp non_portable_subject(path), do: "value at #{inspect(path)}"

  defp instruction_fingerprint(%Jido.Instruction{kind: :flow, target: target}),
    do: Identity.executable_digest(target)

  defp instruction_fingerprint(%Jido.Instruction{kind: :action, target: target}) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary({:action, target, target.module_info(:md5)}, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp valid_id?(id), do: is_binary(id) and byte_size(id) > 0

  defp valid_resume?(continuation) do
    case Map.get(continuation, :resume, :absent) do
      :absent ->
        true

      %{input: input, result: result} = resume when map_size(resume) == 2 ->
        Jido.Exec.Wait.validate_input(input, 0) == :ok and
          (is_nil(result) or match?(%Jido.AgentServer.TurnResult{}, result)) and
          Jido.AgentServer.Status.process_neutral?(resume)

      _other ->
        false
    end
  end

  defp valid_optional_fields?(continuation) do
    valid_resume?(continuation) and valid_terminal_result?(continuation) and
      valid_result_handoff?(continuation)
  end

  defp valid_result_handoff?(continuation),
    do: Map.get(continuation, :result_handoff, true) == true

  defp valid_terminal_result?(continuation) do
    case {Map.get(continuation, :terminal_result, :absent), Map.get(continuation, :completed_at, :absent)} do
      {:absent, :absent} -> true
      {%Jido.AgentServer.TurnResult{} = result, completed_at} -> valid_terminal?(result, completed_at)
      _other -> false
    end
  end

  defp valid_terminal?(result, completed_at) do
    result.status in [:committed, :failed, :cancelled, :timed_out] and
      is_integer(completed_at) and completed_at >= 0 and result.completed_at == completed_at and
      Jido.AgentServer.Status.process_neutral?(result)
  end

  defp valid_keys?(continuation, required) do
    keys = Map.keys(continuation) |> MapSet.new()
    required = MapSet.new(required)

    optional =
      for resume <- [[], [:resume]],
          result <- [[], [:terminal_result, :completed_at]],
          handoff <- [[], [:result_handoff]] do
        MapSet.new(resume ++ result ++ handoff)
      end

    Enum.any?(optional, &(keys == MapSet.union(required, &1)))
  end

  defp maybe_put_result_handoff(continuation, true),
    do: Map.put(continuation, :result_handoff, true)

  defp maybe_put_result_handoff(continuation, false), do: continuation

  defp receipt_status(:committed), do: :completed
  defp receipt_status(:cancelled), do: :cancelled
  defp receipt_status(_status), do: :failed

  defp invalid, do: {:error, Jido.Error.validation_error("invalid execution continuation")}
end

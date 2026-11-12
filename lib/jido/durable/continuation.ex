defmodule Jido.Durable.Continuation do
  @moduledoc false

  alias Jido.Flow.Identity

  @type id :: String.t()
  @type status :: :running | :accepted | :released | :completed | :failed | :cancelled

  @type direct :: %{
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

  @type accepted_handoff :: %{
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

  @type t :: direct() | accepted_handoff() | released_handoff()

  @doc false
  @spec running(map()) :: {:ok, direct()} | {:error, term()}
  def running(%{
        id: id,
        signal: %Jido.Signal{} = signal,
        admitted_signal: %Jido.Signal{} = admitted_signal,
        context: context,
        plugin_inputs: plugin_inputs,
        target: target,
        expires_at: expires_at
      }) do
    continuation = %{
      id: id,
      signal: signal,
      admitted_signal: admitted_signal,
      context: context,
      plugin_inputs: plugin_inputs,
      fingerprint: Identity.executable_digest(target),
      status: :running,
      expires_at: expires_at
    }

    with :ok <- validate(continuation),
         :ok <- portable(continuation),
         do: {:ok, continuation}
  end

  def running(_attrs), do: invalid()

  @doc false
  @spec accept_handoff(map()) :: {:ok, accepted_handoff()} | {:error, term()}
  def accept_handoff(%{
        id: id,
        signal: %Jido.Signal{} = signal,
        context: context,
        instruction: %Jido.Instruction{} = instruction,
        chain_id: chain_id,
        chain_order: chain_order,
        predecessor_id: predecessor_id
      }) do
    continuation = %{
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
             map_size(continuation) in [9, 10] do
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
         valid_resume?(continuation),
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
             map_size(continuation) in [8, 9] do
    if valid_keys?(continuation, [
         :id,
         :status,
         :signal,
         :admitted_signal,
         :context,
         :plugin_inputs,
         :fingerprint,
         :expires_at
       ]) and valid_id?(id) and valid_resume?(continuation),
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
             is_integer(chain_order) and chain_order > 0 and map_size(continuation) in [12, 13] do
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
         valid_resume?(continuation),
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

  defp valid_keys?(continuation, required) do
    keys = Map.keys(continuation) |> MapSet.new()
    required = MapSet.new(required)
    keys == required or keys == MapSet.put(required, :resume)
  end

  defp invalid, do: {:error, Jido.Error.validation_error("invalid execution continuation")}
end

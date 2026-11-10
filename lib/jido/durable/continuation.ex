defmodule Jido.Durable.Continuation do
  @moduledoc """
  Portable data for one suspended or terminal managed execution.

  A continuation keeps a stable Turn identity, accepted Signals, safe context,
  an executable fingerprint, an absolute expiry, and optional Handoff chain
  data. It has no process, timer, storage adapter, or AgentServer state.
  """

  alias Jido.Flow.Component

  @typedoc "A stable Turn identity."
  @type id :: String.t()

  @typedoc "A saved execution state."
  @type status :: :running | :accepted | :released | :completed | :failed | :cancelled

  @typedoc "A direct durable Flow continuation."
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

  @typedoc "An accepted Handoff before successor release."
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

  @typedoc "A released Handoff continuation."
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

  @typedoc "Any portable continuation form."
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
      fingerprint: fingerprint(target),
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

  @doc "Checks the exact shape of one continuation."
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
             map_size(continuation) == 9 do
    if valid_id?(id) and valid_id?(chain_id) and valid_id?(predecessor_id), do: :ok, else: invalid()
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
             map_size(continuation) == 8 do
    if valid_id?(id), do: :ok, else: invalid()
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
             is_integer(chain_order) and chain_order > 0 and map_size(continuation) == 12 do
    if valid_id?(id) and valid_id?(chain_id) and valid_id?(predecessor_id), do: :ok, else: invalid()
  end

  def validate(_continuation), do: invalid()

  @doc "Checks that a continuation contains only storage-safe terms."
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

  defp non_portable_subject([:continuation, :context, key | _path]),
    do: "context key #{inspect(key)}"

  defp non_portable_subject(path), do: "value at #{inspect(path)}"

  @doc false
  @spec compatible(t(), Jido.Instruction.t()) :: :ok | {:error, :execution_definition_changed}
  def compatible(%{fingerprint: fingerprint}, %Jido.Instruction{} = instruction) do
    if instruction_fingerprint(instruction) == fingerprint,
      do: :ok,
      else: {:error, :execution_definition_changed}
  end

  @doc "Returns a stable fingerprint for one Flow definition and its loaded code."
  @spec fingerprint(module() | Jido.Flow.t()) :: String.t()
  def fingerprint(target) do
    flow = if is_atom(target), do: target.flow(), else: target
    versions = versions({:flow, target}, %{}) |> Enum.sort()

    :sha256
    |> :crypto.hash(:erlang.term_to_binary({flow, versions}, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp instruction_fingerprint(%Jido.Instruction{kind: :flow, target: target}),
    do: fingerprint(target)

  defp instruction_fingerprint(%Jido.Instruction{kind: :action, target: target}) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary({:action, target, target.module_info(:md5)}, [:deterministic]))
    |> Base.encode16(case: :lower)
  end

  defp versions({kind, module}, acc) when kind in [:action, :flow] and is_atom(module) do
    if Map.has_key?(acc, module) do
      acc
    else
      acc = Map.put(acc, module, module.module_info(:md5))
      if kind == :flow, do: versions({:flow, module.flow()}, acc), else: acc
    end
  end

  defp versions({:flow, %Jido.Flow{} = flow}, acc) do
    for {_name, node} <- flow.components,
        {_role, instruction, _params} <- Component.calls(node),
        reduce: acc do
      acc -> versions({instruction.kind, instruction.target}, acc)
    end
  end

  defp valid_id?(id), do: is_binary(id) and byte_size(id) > 0
  defp invalid, do: {:error, Jido.Error.validation_error("invalid execution continuation")}
end

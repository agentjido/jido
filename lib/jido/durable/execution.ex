defmodule Jido.Durable.Execution do
  @moduledoc false

  alias Jido.Durable.Ref
  alias Jido.Exec.Runtime
  alias Jido.Flow.Identity
  alias Jido.Instruction
  alias Jido.Signal

  @version 1
  @enforce_keys [:version, :ref, :instruction, :signal, :context, :fingerprint, :exec_opts]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          version: 1,
          ref: Ref.t(),
          instruction: Instruction.t(),
          signal: Signal.t(),
          context: map(),
          fingerprint: String.t(),
          exec_opts: keyword()
        }

  @doc false
  @spec new(Ref.t(), Instruction.t(), Signal.t(), map(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(%Ref{} = ref, %Instruction{kind: :flow} = instruction, %Signal{} = signal, context, exec_opts)
      when is_map(context) and is_list(exec_opts) do
    execution = %__MODULE__{
      version: @version,
      ref: ref,
      instruction: %{instruction | context: %{}},
      signal: signal,
      context: context,
      fingerprint: Identity.executable_digest(instruction.target),
      exec_opts: exec_opts
    }

    with :ok <- validate(execution), do: {:ok, execution}
  end

  def new(_ref, _instruction, _signal, _context, _exec_opts),
    do: {:error, Jido.Error.validation_error("invalid durable execution metadata")}

  @doc false
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(
        %__MODULE__{
          version: @version,
          ref: %Ref{},
          instruction: %Instruction{kind: :flow} = instruction,
          signal: %Signal{},
          context: context,
          fingerprint: fingerprint,
          exec_opts: exec_opts
        } = execution
      )
      when is_map(context) and is_binary(fingerprint) and is_list(exec_opts) do
    with true <- Keyword.keyword?(exec_opts),
         :ok <- Jido.Durable.Runtime.validate_execution_options(exec_opts),
         :ok <- Runtime.portable(instruction),
         :ok <- Runtime.validate_local(context, :context),
         :ok <- Jido.Codec.Term.validate(execution, :durable_execution),
         :ok <- compatible(execution, instruction) do
      :ok
    else
      false -> {:error, Jido.Error.validation_error("durable exec_opts must be a keyword list")}
      {:error, _reason} = error -> error
    end
  end

  def validate(_execution),
    do: {:error, Jido.Error.validation_error("invalid durable execution metadata")}

  defp compatible(%{fingerprint: fingerprint}, %Instruction{kind: :flow, target: target}) do
    if Identity.executable_digest(target) == fingerprint,
      do: :ok,
      else: {:error, :execution_definition_changed}
  end
end

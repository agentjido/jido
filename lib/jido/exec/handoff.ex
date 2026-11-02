defmodule Jido.Exec.Handoff do
  @moduledoc false

  alias Jido.Exec.{Portable, Validation}
  alias Jido.Instruction

  @type t :: %__MODULE__{target: module() | Jido.Flow.t(), kind: :action | :flow, params: map()}
  @enforce_keys [:target, :kind, :params]
  defstruct [:target, :kind, :params]

  @doc false
  @spec new(term(), term()) :: {:ok, t()} | {:error, Exception.t()}
  def new(target, params) do
    with {:ok, instruction} <- Instruction.resolve(target, params),
         :ok <- unbound_runtime(instruction),
         {:ok, _workflow} <- Jido.Exec.compile(instruction),
         {:ok, params} <- Validation.input(instruction.target, instruction.params),
         :ok <- Portable.validate(params, :handoff_input) do
      {:ok, %__MODULE__{target: instruction.target, kind: instruction.kind, params: params}}
    end
  end

  defp unbound_runtime(%Instruction{context: context, metadata: metadata})
       when map_size(context) == 0 and map_size(metadata) == 0,
       do: :ok

  defp unbound_runtime(_instruction),
    do:
      {:error,
       Jido.Action.Error.config_error(
         "handoff target must not bind runtime context or metadata",
         %{reason: :bound_handoff_runtime}
       )}
end

defimpl Runic.Identity.Projectable, for: Jido.Exec.Handoff do
  def identity_document(request) do
    %{
      kind: :jido_handoff,
      version: 1,
      target: target_identity(request.target),
      target_kind: request.kind,
      params: request.params
    }
  end

  defp target_identity(%Jido.Flow{} = flow), do: Jido.Flow.Identity.semantic_digest(flow)
  defp target_identity(module), do: module
end

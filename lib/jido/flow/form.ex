defmodule Jido.Flow.Form do
  @moduledoc false

  alias Jido.Flow.{Call, Error}
  alias Jido.Flow.Form.{Choice, Invoke, Iterate, Parallel, Reduce, Semantics, Validation, Wait}
  alias Jido.Flow.Form.Map, as: MapForm
  alias Jido.Instruction

  @type t ::
          Call.t()
          | MapForm.t()
          | Reduce.t()
          | Choice.t()
          | Parallel.t()
          | Iterate.t()
          | Invoke.t()
          | Wait.t()

  @doc false
  @spec normalize(term()) :: {:ok, t()} | {:error, Exception.t()}
  def normalize(%Call{} = call), do: Validation.normalize_call(call, :flow, "Flow Step")

  def normalize(%Instruction{} = instruction),
    do: Validation.normalize_call(instruction, :flow, "Flow Step")

  def normalize(%MapForm{} = form), do: MapForm.normalize(form)
  def normalize(%Reduce{} = form), do: Reduce.normalize(form)
  def normalize(%Choice{} = form), do: Choice.normalize(form)
  def normalize(%Parallel{} = form), do: Parallel.normalize(form)
  def normalize(%Iterate{} = form), do: Iterate.normalize(form)
  def normalize(%Invoke{} = form), do: Invoke.normalize(form)
  def normalize(%Wait{} = form), do: Wait.normalize(form)

  def normalize(%{__struct__: _module} = form), do: invalid_form(form)

  def normalize(%{} = form) when not is_struct(form) do
    case Map.get(form, :type, Map.get(form, "type")) do
      type when type in [:map, "map"] -> MapForm.normalize(form)
      type when type in [:reduce, "reduce"] -> Reduce.normalize(form)
      type when type in [:choice, "choice"] -> Choice.normalize(form)
      type when type in [:parallel, "parallel"] -> Parallel.normalize(form)
      type when type in [:iterate, "iterate"] -> Iterate.normalize(form)
      type when type in [:invoke, "invoke"] -> Invoke.normalize(form)
      type when type in [:wait, "wait"] -> Wait.normalize(form)
      _type -> Validation.normalize_call(form, :flow, "Flow Step")
    end
  end

  def normalize(value), do: Validation.normalize_call(value, :flow, "Flow Step")

  @doc false
  @spec result_refs(t()) :: [String.t()]
  defdelegate result_refs(form), to: Semantics

  @doc false
  @spec identity_data(map()) :: map()
  defdelegate identity_data(flow), to: Semantics

  defp invalid_form(form) do
    {:error, Error.validation_error("Flow form is not supported", %{reason: :form, value: form})}
  end
end

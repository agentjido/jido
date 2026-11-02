defmodule Jido.Flow.Form.Semantics do
  @moduledoc false

  alias Jido.Flow.{Call, Value}
  alias Jido.Flow.Form.{Choice, Invoke, Iterate, Parallel, Reduce, Wait}
  alias Jido.Flow.Form.Map, as: MapForm

  @doc false
  @spec result_refs(term()) :: [String.t()]
  def result_refs(%Call{} = call), do: Call.result_refs(call)

  def result_refs(%MapForm{} = form) do
    Value.result_refs(form.collection) ++ Call.result_refs(form.call)
  end

  def result_refs(%Reduce{} = form) do
    Value.result_refs(form.collection) ++
      Value.result_refs(form.initial) ++ Call.result_refs(form.call)
  end

  def result_refs(%Choice{} = form) do
    option_refs =
      Enum.flat_map(form.options, fn {_name, condition, call} ->
        Value.result_refs(condition) ++ Call.result_refs(call)
      end)

    option_refs ++ Call.result_refs(form.fallback)
  end

  def result_refs(%Parallel{} = form) do
    Enum.flat_map(form.actions, fn {_name, call} -> Call.result_refs(call) end)
  end

  def result_refs(%Iterate{} = form) do
    condition_refs =
      case form.mode do
        {:repeat, _count} -> []
        {:while, condition, _maximum} -> Value.result_refs(condition)
      end

    Value.result_refs(form.initial) ++
      condition_refs ++ Call.result_refs(form.call) ++ Value.result_refs(form.update)
  end

  def result_refs(%Invoke{} = form) do
    Value.result_refs(form.target) ++ Value.result_refs(form.params)
  end

  def result_refs(%Wait{} = form) do
    Enum.flat_map(form.clauses, fn
      {:event, _name, _event, match} -> Value.result_refs(match)
      {:timer, _name, _delay} -> []
    end)
  end

  @doc false
  @spec identity(term()) :: term()
  def identity(%Call{} = call), do: {:call, call_identity(call)}

  def identity(%MapForm{} = form) do
    {"map", {form.collection, identity(form.call), form.on_error}}
  end

  def identity(%Reduce{} = form) do
    {"reduce", {form.collection, form.initial, identity(form.call)}}
  end

  def identity(%Choice{} = form) do
    options =
      Enum.map(form.options, fn {name, condition, call} ->
        {name, condition, identity(call)}
      end)

    {"choice", {options, identity(form.fallback)}}
  end

  def identity(%Parallel{} = form) do
    actions = Enum.map(form.actions, fn {name, call} -> {name, identity(call)} end)
    {"parallel", {actions, form.on_error}}
  end

  def identity(%Iterate{} = form) do
    data = {form.mode, form.state_schema, form.initial, identity(form.call), form.update}
    {"iterate", data}
  end

  def identity(%Invoke{} = form) do
    targets =
      form.targets
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {id, target} -> {id, target_identity(target)} end)

    {"invoke", {form.target, targets, form.params, form.policy, form.on_error}}
  end

  def identity(%Wait{} = form), do: {"wait", form.clauses}

  @doc false
  @spec identity_data(map()) :: map()
  def identity_data(flow) do
    %{
      name: flow.name,
      schema: flow.schema,
      output_schema: flow.output_schema,
      forms:
        flow.forms
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {id, form} -> {id, identity(form)} end),
      needs: Enum.sort(flow.needs),
      output: flow.output
    }
  end

  defp call_identity(%Call{instruction: instruction, policy: policy, on_error: on_error}) do
    {
      target_identity(instruction.target),
      instruction.params,
      instruction.context,
      policy,
      on_error
    }
  end

  defp target_identity(target), do: target
end

defmodule JidoActionTest.FlowComponent do
  @moduledoc false

  alias Jido.Flow.Definition

  for kind <- [:step, :subflow, :choice, :map, :reduce, :iterate, :invoke, :handoff] do
    bang = String.to_atom("#{kind}!")

    def unquote(kind)(attrs), do: build(unquote(kind), attrs)

    def unquote(bang)(attrs) do
      case build(unquote(kind), attrs) do
        {:ok, component} -> component
        {:error, error} -> raise error
      end
    end
  end

  def option(attrs) do
    attrs = attrs |> attributes!() |> Map.put_new(:params, %{})

    with {:ok, {_name, %{options: [option]}}} <-
           Definition.component(%{
             kind: :choice,
             name: "fixture",
             options: [attrs],
             fallback: %{action: __MODULE__}
           }) do
      instruction = option.call
      params = instruction.params

      {:ok,
       %{
         name: option.name,
         condition: option.condition,
         action: instruction.target,
         params: params
       }}
    end
  end

  def option!(attrs), do: unwrap!(option(attrs))

  def fallback(attrs) do
    attrs = attrs |> attributes!() |> Map.put_new(:params, %{})

    with {:ok, {_name, %{fallback: %{params: params} = instruction}}} <-
           Definition.component(%{
             kind: :choice,
             name: "fixture",
             options: [%{name: "fixture", condition: true, action: __MODULE__}],
             fallback: attrs
           }) do
      {:ok, %{action: instruction.target, params: params}}
    end
  end

  def fallback!(attrs), do: unwrap!(fallback(attrs))

  def state(attrs) do
    attrs = attrs |> attributes!() |> Map.put_new(:schema, Zoi.map())

    with {:ok, {_name, %{state: state}}} <-
           Definition.component(%{
             kind: :iterate,
             name: "fixture",
             action: __MODULE__,
             state: attrs,
             completion: true,
             max_iterations: 1
           }) do
      {:ok, state}
    end
  end

  def state!(attrs), do: unwrap!(state(attrs))

  def to_definition(components),
    do: components |> Definition.to_definition() |> Enum.map(&authoring/1)

  def component_to_definition(component),
    do: component |> Definition.component_to_definition() |> authoring()

  defp build(kind, attrs) do
    attrs =
      attrs
      |> attributes!()
      |> normalize_nested(kind)
      |> Map.put(:kind, kind)

    with {:ok, named_component} <- Definition.component(attrs) do
      {:ok, component_to_definition(named_component)}
    end
  end

  defp normalize_nested(attrs, :choice) do
    attrs
    |> Map.update(:options, [], fn options -> Enum.map(options, &attributes!/1) end)
    |> Map.update(:fallback, nil, fn
      nil -> nil
      fallback -> attributes!(fallback)
    end)
  end

  defp normalize_nested(attrs, :iterate) do
    Map.update(attrs, :state, nil, fn
      nil -> nil
      state -> attributes!(state)
    end)
  end

  defp normalize_nested(attrs, _kind), do: attrs

  defp authoring(%{kind: :call, call: call} = attrs) do
    {kind, target_field} = if call.kind == :action, do: {:step, :action}, else: {:subflow, :flow}

    attrs
    |> Map.delete(:call)
    |> Map.put(:kind, kind)
    |> Map.put(target_field, call.target)
    |> Map.put(:params, call.params)
  end

  defp authoring(%{kind: :choice} = attrs) do
    attrs
    |> Map.update!(:options, fn options -> Enum.map(options, &flat_call/1) end)
    |> Map.update!(:fallback, &%{action: &1.target, params: &1.params})
  end

  defp authoring(%{kind: :invoke, decision: decision, expander: expander} = attrs) do
    %{attrs | decision: decision.target, expander: expander.target}
    |> Map.put(:params, decision.params)
  end

  defp authoring(%{kind: :handoff, selector: selector} = attrs) do
    %{attrs | selector: selector.target}
    |> Map.put(:params, selector.params)
  end

  defp authoring(attrs), do: flat_call(attrs)

  defp flat_call(%{call: call} = attrs) do
    attrs
    |> Map.delete(:call)
    |> Map.put(:action, call.target)
    |> Map.put(:params, call.params)
  end

  defp attributes!(attrs) when is_map(attrs) and not is_struct(attrs), do: attrs

  defp attributes!(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      Map.new(attrs)
    else
      raise ArgumentError, "expected Flow component attributes to be a map or keyword list"
    end
  end

  defp attributes!(_attrs),
    do: raise(ArgumentError, "expected Flow component attributes to be a map or keyword list")

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)
end

defmodule JidoActionTest.FlowBuilder do
  @moduledoc false

  def new(attrs) when is_list(attrs) do
    if Keyword.keyword?(attrs) do
      attrs |> Map.new() |> Jido.Flow.new()
    else
      Jido.Flow.new(attrs)
    end
  end

  def new(%Jido.Flow{} = flow), do: Jido.Flow.validate(flow)
  def new(attrs), do: Jido.Flow.new(attrs)

  def new!(attrs) do
    case new(attrs) do
      {:ok, flow} -> flow
      {:error, error} -> raise error
    end
  end
end

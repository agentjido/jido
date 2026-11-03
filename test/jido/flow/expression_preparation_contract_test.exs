defmodule Jido.Flow.ValuePreparationContractTest do
  use ExUnit.Case, async: true

  alias Jido.Flow.Definition
  alias Jido.Error.ValidationError
  alias Jido.Flow.Ref
  alias JidoActionTest.Fixtures.Actions.Add
  alias JidoActionTest.Fixtures.NestedFlow

  test "every call form normalizes nested result names and treats nil params as empty" do
    params = %{nested: [%Ref{source: :result, component: :source, path: []}]}
    expected = %{nested: [Ref.result("source")]}

    for {attrs, role, _scope} <- call_cases(params) do
      assert {:ok, {_name, node}} = Definition.component(attrs)
      assert call_params(node, role) == expected
    end

    for {attrs, role, _scope} <- call_cases(nil) do
      assert {:ok, {_name, node}} = Definition.component(attrs)
      assert call_params(node, role) == %{}
    end
  end

  test "normalization failures precede scope validation across each call value" do
    params = [Ref.body_result(), %Ref{source: :result, component: "", path: []}]
    {:error, message} = Jido.Codec.Config.validate_name("")

    for {attrs, _role, _scope} <- call_cases(params) do
      assert {:error, %ValidationError{} = error} = Definition.component(attrs)
      assert error.message == message
      assert List.last(error.details.path) == 1
      assert :params in error.details.path
    end
  end

  test "parameter scopes report the exact nested path" do
    for {attrs, role, scope} <- call_cases(%{}) do
      attrs = put_call_params(attrs, role, %{nested: [scope_ref(scope)]})

      assert {:error, error} = Definition.component(attrs)
      assert error.message == "flow expression contains a scoped ref outside its valid scope"
      assert error.details.ref_type == scope_ref(scope).source
      assert error.details.scope == scope
      assert Enum.take(error.details.path, -3) == [:params, :nested, 0]
    end
  end

  test "required expression fields distinguish nil from absence" do
    assert {:ok, {"map", %{collection: nil}}} =
             Definition.component(%{kind: :map, name: "map", collection: nil, action: Add})

    assert {:ok, {"reduce", %{collection: nil, initial: nil}}} =
             Definition.component(%{
               kind: :reduce,
               name: "reduce",
               collection: nil,
               initial: nil,
               action: Add
             })

    assert {:ok, {"iterate", %{state: %{initial: nil, update: nil}}}} =
             Definition.component(%{
               kind: :iterate,
               name: "iterate",
               action: Add,
               state: %{initial: nil, update: nil},
               completion: true,
               max_iterations: 1
             })

    for {attrs, message, field} <- [
          {%{kind: :map, name: "map", action: Add}, "Flow field is required", :collection},
          {%{kind: :reduce, name: "reduce", collection: [], action: Add}, "Flow field is required", :initial},
          {%{
             kind: :iterate,
             name: "iterate",
             action: Add,
             state: %{initial: nil},
             completion: true,
             max_iterations: 1
           }, "Flow field is required", :update}
        ] do
      assert {:error, error} = Definition.component(attrs)
      assert error.message == message
      assert List.last(error.details.path) == field
    end
  end

  test "nested Choice errors retain component, option, and expression path segments" do
    choice = %{
      kind: :choice,
      name: "route",
      options: [
        %{name: "yes", condition: true, action: Add, params: %{nested: [self()]}}
      ],
      fallback: %{action: Add}
    }

    assert {:error, local} = Definition.component(choice)
    assert local.details.path == [:options, 0, :call, :params, :nested, 0]

    assert {:error, nested} =
             Jido.Flow.new(%{name: "nested", components: [choice], output: %{}})

    assert nested.message == local.message
    assert nested.details.path == [:components, 0, :options, 0, :call, :params, :nested, 0]
  end

  defp call_cases(params) do
    [
      {%{kind: :step, name: "step", action: Add, params: params}, :call, :flow},
      {%{kind: :subflow, name: "child", flow: NestedFlow, params: params}, :call, :flow},
      {%{
         kind: :choice,
         name: "option",
         options: [%{name: "yes", condition: true, action: Add, params: params}],
         fallback: %{action: Add}
       }, "yes", :flow},
      {%{
         kind: :choice,
         name: "fallback",
         options: [%{name: "yes", condition: true, action: Add}],
         fallback: %{action: Add, params: params}
       }, :fallback, :flow},
      {%{kind: :map, name: "map", collection: [], action: Add, params: params}, :map, :map_params},
      {%{
         kind: :reduce,
         name: "reduce",
         collection: [],
         initial: %{},
         action: Add,
         params: params
       }, :reduce, :reduce_params},
      {%{
         kind: :iterate,
         name: "iterate",
         action: Add,
         params: params,
         state: %{initial: %{}, update: %{}},
         completion: true,
         max_iterations: 1
       }, :iterate, :iterate_params},
      {%{
         kind: :invoke,
         name: "invoke",
         decision: Add,
         expander: Add,
         params: params
       }, :decision, :flow}
    ]
  end

  defp call_params(node, role) do
    {_role, _instruction, params} =
      Enum.find(Definition.calls(node), fn {call_role, _instruction, _params} ->
        call_role == role
      end)

    params
  end

  defp put_call_params(%{kind: :choice} = attrs, "yes", params),
    do: put_in(attrs, [:options, Access.at(0), :params], params)

  defp put_call_params(%{kind: :choice} = attrs, :fallback, params),
    do: put_in(attrs, [:fallback, :params], params)

  defp put_call_params(attrs, _role, params), do: Map.put(attrs, :params, params)

  defp scope_ref(:iterate_params), do: Ref.item()
  defp scope_ref(_scope), do: Ref.body_result()
end

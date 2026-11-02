defmodule Jido.Flow.FormTest do
  use ExUnit.Case, async: true

  require Jido.Authoring.Limits

  alias Jido.Flow
  alias Jido.Flow.Form

  defmodule Echo do
    use Jido.Action, name: "flow_form_test_echo"

    @impl true
    def run(params, _context), do: {:ok, params}
  end

  test "uses closed direct form dispatch without a handler registry" do
    assert Code.ensure_loaded?(Jido.Flow.Form.Validation)
    assert Code.ensure_loaded?(Jido.Flow.Form.Semantics)

    for module <- [
          Jido.Flow.Form.Map,
          Jido.Flow.Form.Reduce,
          Jido.Flow.Form.Choice,
          Jido.Flow.Form.Parallel,
          Jido.Flow.Form.Iterate,
          Jido.Flow.Form.Invoke,
          Jido.Flow.Form.Wait
        ] do
      refute function_exported?(module, :__jido_flow_builtin__, 0)
    end

    refute function_exported?(Form, :handler, 1)
    refute function_exported?(Form, :handler_for_tag, 1)
    refute function_exported?(Form, :tag, 1)
  end

  test "DSL construction stays separate from the canonical form model" do
    assert Code.ensure_loaded?(Jido.Flow.DSL.Builder)
    assert function_exported?(Jido.Flow.DSL.Builder, :build, 3)
    refute Code.ensure_loaded?(Jido.Flow.DSL.Lowerer)

    for module <- [
          Jido.Flow.Form.Map,
          Jido.Flow.Form.Reduce,
          Jido.Flow.Form.Choice,
          Jido.Flow.Form.Parallel,
          Jido.Flow.Form.Iterate,
          Jido.Flow.Form.Invoke,
          Jido.Flow.Form.Wait
        ],
        callback <- [build_dsl: 1, encode: 2, decode: 3] do
      refute function_exported?(module, elem(callback, 0), elem(callback, 1))
    end

    refute Code.ensure_loaded?(Jido.Flow.Form.Support)
    refute Code.ensure_loaded?(Jido.Flow.Form.Choice.Macros)
    refute Code.ensure_loaded?(Jido.Flow.Form.Choice.Entity)
    assert Code.ensure_loaded?(Jido.Flow.DSL.Forms)
  end

  test "canonical data modules do not own adapter or runtime helpers" do
    refute function_exported?(Jido.Flow.CallPolicy, :dsl_schema, 0)
    refute function_exported?(Jido.Flow.CallPolicy, :encode, 1)
    refute function_exported?(Jido.Flow.CallPolicy, :retry_delay, 2)
    refute function_exported?(Jido.Flow.Config, :prepare!, 2)
  end

  test "Invoke has one canonical form struct" do
    assert %Jido.Flow.Form.Invoke{} =
             Jido.Flow.new!(%{
               name: "invoke_form",
               forms: %{
                 invoke: %{
                   type: :invoke,
                   target: Jido.Flow.Ref.input(:target),
                   targets: %{"echo" => Echo},
                   params: %{}
                 }
               },
               output: Jido.Flow.Ref.result(:invoke)
             }).forms["invoke"]

    refute Code.ensure_loaded?(Jido.Flow.Call.Dynamic)
  end

  test "all canonical form collections use the authoring collection limit" do
    maximum = Jido.Authoring.Limits.maximum_collection_size()
    names = Enum.map(0..maximum, &Integer.to_string/1)
    call = Echo

    values = [
      %{type: :choice, options: Enum.map(names, &{&1, true, call}), fallback: call},
      %{type: :parallel, actions: Enum.map(names, &{&1, call})},
      %{type: :invoke, target: "0", targets: Map.new(names, &{&1, call})},
      %{type: :wait, clauses: Enum.map(names, &{:timer, &1, 0})}
    ]

    for value <- values do
      assert {:error, error} = Form.normalize(value)
      assert error.details.reason == :collection
      assert error.details.maximum_size == maximum
    end
  end

  test "a canonical Flow limits its named forms before normalization" do
    maximum = Jido.Authoring.Limits.maximum_collection_size()
    forms = Map.new(0..maximum, &{Integer.to_string(&1), Echo})

    assert {:error, error} =
             Flow.new(%{name: "too_many_forms", forms: forms, output: %{}})

    assert error.details.reason == :collection
    assert error.details.maximum_size == maximum
  end
end

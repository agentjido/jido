defmodule Jido.Flow.BoundaryValidationTest do
  use ExUnit.Case, async: true

  defmodule InvalidChildFlow do
    @behaviour Jido.Flow
    def flow, do: :invalid
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule RaisingChildFlow do
    @behaviour Jido.Flow
    def flow, do: raise("child definition failed")
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(_params, _context), do: {:ok, %{}}
  end

  defmodule ThrowingChildFlow do
    @behaviour Jido.Flow
    def flow, do: throw(:child_definition_failed)
    def validate_params(params), do: {:ok, params}
    def validate_output(output), do: {:ok, output}
    def run(_params, _context), do: {:ok, %{}}
  end

  alias Jido.Flow
  alias Jido.Flow.Definition
  alias Jido.Flow.Error.InvalidDefinitionError
  alias Jido.Flow.Ref
  alias Jido.Flow.Value
  alias JidoActionTest.Fixtures.Actions.{Add, MissingRun}

  test "portable data rejects invalid containers, values, and keys" do
    assert {:error, _error} = Value.validate_object([])
    assert {:error, _error} = Value.validate_data([:ok | :tail])
    assert {:error, _error} = Value.validate_data(%{ok: [:good, self()]})

    for value <- [{:tuple}, fn -> :ok end, self(), make_ref(), %URI{}, hd(Port.list())] do
      assert {:error, error} = Value.validate_data(value)
      assert Exception.message(error) == "flow data contains an unsupported value"
    end

    for key <- [-1, nil, {:tuple}] do
      assert {:error, error} = Value.validate_data(%{key => :value})
      assert Exception.message(error) == "flow data contains an unsupported map key"
    end
  end

  test "portable data keeps nested error paths and rejects improper lists first" do
    for {value, message, path} <- [
          {%{outer: [0, %{inner: self()}]}, "flow data contains an unsupported value", [:outer, 1, :inner]},
          {%{outer: [0, %{nil: :value}]}, "flow data contains an unsupported map key", [:outer, 1]},
          {%{outer: [0, <<255>>]}, "flow data strings must be valid UTF-8", [:outer, 1]},
          {%{outer: [0, %{<<255>> => :value}]}, "flow data strings must be valid UTF-8", [:outer, 1]},
          {%{outer: [[self() | :tail]]}, "flow data must contain proper lists", [:outer, 0]}
        ] do
      assert {:error, error} = Value.validate_data(value)
      assert error.message == message
      assert error.details.path == path
    end
  end

  test "Definition validates common component fields" do
    for attrs <- components() do
      assert {:ok, {name, node}} = Definition.component(attrs)
      assert name == attrs.name
      assert Definition.needs(node) == []
      assert is_map(node.meta)
    end

    assert {:error, _error} = Definition.component(:bad)
    assert {:error, _error} = Definition.name(1)

    for attrs <- components() do
      assert {:error, %InvalidDefinitionError{}} =
               attrs
               |> Map.put(:needs, ["one", "one"])
               |> Definition.component()

      assert {:error, %InvalidDefinitionError{}} =
               attrs
               |> Map.put(:meta, %{self() => :bad})
               |> Definition.component()
    end
  end

  test "component maps return clear boundary errors" do
    invalid = [
      :bad,
      %{kind: :map, name: "map", action: Add},
      %{kind: :map, name: "map", collection: [], action: Add, on_error: :bad},
      %{kind: :reduce, name: "reduce", collection: [], action: Add},
      %{kind: :iterate, name: "iterate", action: Add},
      %{
        kind: :iterate,
        name: "iterate",
        action: Add,
        state: %{initial: %{}, update: %{}},
        completion: true,
        max_iterations: 0
      }
    ]

    for attrs <- invalid do
      assert {:error, error} = Definition.component(attrs)
      assert is_exception(error)
    end
  end

  test "Iterate state rejects incomplete and unknown authoring data" do
    schema = Jido.Joi.map()

    valid = %{
      kind: :iterate,
      name: "iterate",
      action: Add,
      state: %{schema: schema, initial: %{}, update: %{}},
      completion: true,
      max_iterations: 1
    }

    assert {:ok, {"iterate", %{state: %{schema: ^schema, initial: %{}, update: %{}}}}} =
             Definition.component(valid)

    for state <- [
          :bad,
          [:not_keyword],
          %{schema: Jido.Joi.map(), initial: %{}, update: %{}, extra: true},
          %{schema: fn -> :bad end, initial: %{}, update: %{}},
          %{schema: Jido.Joi.map(), update: %{}},
          %{schema: Jido.Joi.map(), initial: %{}}
        ] do
      assert {:error, %InvalidDefinitionError{}} =
               valid
               |> Map.put(:state, state)
               |> Definition.component()
    end
  end

  test "reference helpers and map definitions produce the canonical Flow" do
    assert %Ref{source: :context} = Ref.context(:request_id)
    assert %Ref{source: :item_index} = Ref.item_index()
    assert %Ref{source: :item_id} = Ref.item_id()
    assert %Ref{path: [:value]} = Ref.select(Ref.input([]), :value)

    assert Enum.all?(
             [
               Jido.Expr.new!(:!=, [1, 2]),
               Jido.Expr.new!(:<, [1, 2]),
               Jido.Expr.new!(:<=, [1, 2]),
               Jido.Expr.new!(:>, [2, 1]),
               Jido.Expr.new!(:in, [1, [1]]),
               Jido.Expr.new!(:and, [true, Jido.Expr.new!(:==, [1, 1])]),
               Jido.Expr.new!(:or, [false, Jido.Expr.new!(:==, [1, 1])]),
               Jido.Expr.new!(:not, [Jido.Expr.new!(:==, [1, 2])])
             ],
             &match?(%Jido.Expr{}, &1)
           )

    assert {:ok, %Flow{components: components}} =
             Flow.new(%{
               name: "all_data_components",
               components: Enum.drop(components(), 2),
               output: %{}
             })

    assert Map.keys(components) |> Enum.sort() == ["choice", "iterate", "map", "reduce"]

    assert {:error, %InvalidDefinitionError{}} =
             Flow.new(%{
               name: "invalid",
               components: [%{kind: :step, name: "bad", action: nil}],
               output: %{}
             })

    assert {:error, _error} = Flow.new([:not_keyword])
    assert {:error, _error} = Flow.new(:bad)
  end

  test "Flow validation rejects invalid root shapes and fields" do
    for attrs <- [
          :bad,
          %{name: 1, output: %{}},
          %{name: "flow", description: 1, output: %{}},
          %{name: "flow", schema: fn -> :bad end, output: %{}},
          %{name: "flow", components: :bad, output: %{}},
          %{name: "flow", output: nil},
          %{name: "flow", unexpected: true, output: %{}}
        ] do
      assert {:error, error} = Flow.new(attrs)
      assert is_exception(error)
    end

    duplicate = %{kind: :step, name: "same", action: Add}

    assert {:error, _error} =
             Flow.new(%{
               name: "duplicate",
               components: [duplicate, duplicate],
               output: %{}
             })

    assert {:error, _error} = Flow.__validate_config__(:bad)

    invalid_target =
      Flow.new!(%{
        name: "invalid_target",
        components: [%{kind: :step, name: "missing", action: MissingRun}],
        output: Ref.result("missing")
      })

    assert {:error, _error} = Jido.Exec.Compiler.validate(invalid_target)
    valid_step = %{kind: :step, name: "step", action: Add}

    assert {:error, _error} =
             Flow.new(%{name: "", components: [valid_step], output: Ref.result("step")})

    assert {:ok, %Flow{} = flow} =
             Flow.new(%{
               name: "nil_schemas",
               schema: nil,
               output_schema: nil,
               components: [valid_step],
               output: Ref.result("step")
             })

    assert Jido.Joi.Schema.kind(flow.schema) == :map
    assert Jido.Joi.Schema.kind(flow.output_schema) == :map

    assert {:error, _error} =
             Flow.new(%{name: "bad_component", components: [:bad], output: %{}})

    assert {:error, _error} =
             Flow.new(%{name: "missing_output", components: [valid_step], output: nil})
  end

  test "Flow executable validation contains invalid child definitions" do
    for module <- [InvalidChildFlow, RaisingChildFlow, ThrowingChildFlow] do
      flow =
        Flow.new!(%{
          name: "invalid_child",
          components: [%{kind: :subflow, name: "child", flow: module}],
          output: Ref.result("child")
        })

      assert {:error, %InvalidDefinitionError{}} = Jido.Exec.Compiler.validate(flow)
    end
  end

  test "Choice maps reject incomplete and duplicate routing data" do
    condition = Jido.Expr.new!(:==, [true, true])
    valid_option = %{name: "yes", condition: condition, action: Add}
    valid_fallback = %{action: Add}
    valid = %{kind: :choice, name: "route", options: [valid_option], fallback: valid_fallback}

    assert {:ok, {"route", %{kind: :choice, options: [_], fallback: %{params: %{}}}}} =
             Definition.component(valid)

    invalid = [
      %{valid | options: []},
      %{valid | options: :bad},
      %{valid | options: [valid_option | :tail]},
      %{valid | fallback: nil},
      %{valid | options: [valid_option, valid_option]},
      %{valid | options: [Map.delete(valid_option, :condition)]},
      %{valid | options: [Map.put(valid_option, :extra, true)]},
      %{valid | fallback: Map.put(valid_fallback, :extra, true)}
    ]

    for attrs <- invalid do
      assert {:error, error} = Definition.component(attrs)
      assert is_exception(error)
    end
  end

  test "Value rejects invalid refs, scope, lists, and names" do
    assert {:error, invalid_scope} = Value.validate(Ref.item(), :flow)
    assert invalid_scope.details == %{path: [], ref_type: :item, scope: :flow}
    invalid_ref = %Ref{source: :unsupported, component: nil, path: []}
    assert {:error, invalid_ref_error} = Value.validate(invalid_ref)
    assert invalid_ref_error.details == %{path: [], ref_type: :unsupported}
    assert {:error, improper} = Value.validate([1 | :tail])
    assert improper.details.reason == :improper_list
    assert {:error, _error} = Value.normalize([Ref.result("ok") | :tail])
    atom_result_ref = %Ref{source: :result, component: :component, path: []}
    assert Value.normalize(atom_result_ref) == {:ok, Ref.result("component")}
    assert {:error, name_error} = Value.normalize(Ref.result(""))
    assert Exception.message(name_error) == "Action name cannot be blank."
  end

  test "Value preserves nested validation and normalization errors" do
    assert {:error, scoped_error} = Value.validate([Ref.item()], :flow)
    assert scoped_error.details == %{path: [0], ref_type: :item, scope: :flow}
    invalid_result_ref = %Ref{source: :result, component: "", path: []}
    assert {:error, normalization_error} = Value.normalize([%{result: invalid_result_ref}])
    assert Exception.message(normalization_error) == "Action name cannot be blank."
  end

  defp components do
    [
      %{kind: :step, name: "step", action: Add},
      %{kind: :subflow, name: "child", flow: JidoActionTest.Fixtures.NestedFlow},
      %{
        kind: :choice,
        name: "choice",
        options: [%{name: "yes", condition: true, action: Add}],
        fallback: %{action: Add}
      },
      %{kind: :map, name: "map", collection: [], action: Add},
      %{kind: :reduce, name: "reduce", collection: [], initial: %{}, action: Add},
      %{
        kind: :iterate,
        name: "iterate",
        action: Add,
        state: %{initial: %{}, update: %{}},
        completion: true,
        max_iterations: 1
      }
    ]
  end
end

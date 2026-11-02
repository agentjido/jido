Enum.each(
  [
    JidoActionTest.Fixtures.ConcurrencyProbeAction,
    JidoActionTest.Fixtures.Transforms,
    JidoActionTest.Fixtures.Actions.Add,
    JidoActionTest.Fixtures.Actions.EchoParamsAction,
    JidoActionTest.Fixtures.Actions.ErrorAction,
    JidoActionTest.Fixtures.Actions.KillingAction,
    JidoActionTest.Fixtures.Actions.Multiply,
    JidoActionTest.Fixtures.Actions.OutputEnvelopeAction
  ],
  &Code.ensure_compiled!/1
)

Code.ensure_compiled!(JidoActionTest.Fixtures.Execution.BlockingAction)

defmodule JidoActionTest.Fixtures.CountedValidationFlow do
  @moduledoc false
  use Jido.Flow,
    name: "counted_validation_flow",
    schema:
      Zoi.map()
      |> Zoi.transform({JidoActionTest.Fixtures.Transforms, :count, [:input]}),
    output_schema:
      Zoi.map()
      |> Zoi.transform({JidoActionTest.Fixtures.Transforms, :count, [:output]})

  flow do
    step("echo",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value), input_passes: input(:input_passes)}
    )

    output(result("echo"))
  end
end

defmodule JidoActionTest.Fixtures.ScalarTransformedOutputFlow do
  @moduledoc false
  use Jido.Flow,
    name: "scalar_transformed_output_flow",
    output_schema:
      Zoi.map()
      |> Zoi.transform({JidoActionTest.Fixtures.Transforms, :count, [:invalid_output]})

  flow do
    step("echo",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(result("echo"))
  end
end

defmodule JidoActionTest.Fixtures.ScalarTransformedInputFlow do
  @moduledoc false
  use Jido.Flow,
    name: "scalar_transformed_input_flow",
    schema:
      Zoi.map()
      |> Zoi.transform({JidoActionTest.Fixtures.Transforms, :count, [:invalid_input]})

  flow do
    step("echo",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(result("echo"))
  end
end

defmodule JidoActionTest.Fixtures.EnvelopeFlow do
  @moduledoc false
  use Jido.Flow,
    name: "envelope_flow",
    output_schema:
      Zoi.map()
      |> Zoi.transform({JidoActionTest.Fixtures.Transforms, :count, [:envelope_output]})

  flow do
    step("envelope",
      action: JidoActionTest.Fixtures.Actions.OutputEnvelopeAction,
      params: %{value: input(:value)}
    )

    output(result("envelope"))
  end
end

defmodule JidoActionTest.Fixtures.ScalarResultFlow do
  @moduledoc false
  use Jido.Flow, name: "scalar_result_flow"

  flow do
    step("echo",
      action: JidoActionTest.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(select(result("echo"), [:value]))
  end
end

defmodule JidoActionTest.Fixtures.MathFlow do
  @moduledoc false
  use Jido.Flow,
    name: "math_flow",
    description: "Adds one and doubles the result"

  flow do
    step("add_one",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    step("double",
      action: JidoActionTest.Fixtures.Actions.Multiply,
      params: %{value: select(result("add_one"), [:value]), amount: 2}
    )

    output(result("double"))
  end
end

defmodule JidoActionTest.Fixtures.AsyncMathFlow do
  @moduledoc false
  use Jido.Flow,
    name: "async_math_flow",
    description: "Runs through Exec options"

  flow do
    step("add_one",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    output(result("add_one"))
  end
end

defmodule JidoActionTest.Fixtures.BlockingFlow do
  @moduledoc false
  use Jido.Flow, name: "blocking_flow"

  flow do
    step("blocking",
      action: JidoActionTest.Fixtures.Execution.BlockingAction,
      params: %{value: input(:value)}
    )

    output(result("blocking"))
  end
end

defmodule JidoActionTest.Fixtures.KillingFlow do
  @moduledoc false
  use Jido.Flow, name: "killing_flow"

  flow do
    step("kill", action: JidoActionTest.Fixtures.Actions.KillingAction, params: %{})
    output(result("kill"))
  end
end

defmodule JidoActionTest.Fixtures.ChoicePublicPaths do
  @moduledoc false
  use Jido.Flow, name: "choice_public_paths"

  alias JidoActionTest.Fixtures.Actions.Add

  flow do
    choice "route" do
      option "priority" do
        condition(input(:kind) == :priority)
        action(JidoActionTest.Fixtures.Actions.Add)
        params(%{value: input(:value), amount: 1})
      end

      otherwise action: Add, params: %{value: input(:value), amount: 2}
    end

    output(result("route"))
  end
end

defmodule JidoActionTest.Fixtures.TelemetryChildFlow do
  @moduledoc false
  use Jido.Flow, name: "telemetry_child_flow"

  flow do
    step("child_add",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value)}
    )

    output(result("child_add"))
  end
end

Code.ensure_compiled!(JidoActionTest.Fixtures.TelemetryChildFlow)

defmodule JidoActionTest.Fixtures.TelemetryParentFlow do
  @moduledoc false
  use Jido.Flow, name: "telemetry_parent_flow"

  flow do
    step("child",
      action: JidoActionTest.Fixtures.TelemetryChildFlow,
      params: %{value: input(:value)}
    )

    output(result("child"))
  end
end

Code.ensure_compiled!(JidoActionTest.Fixtures.Increment)
Code.ensure_compiled!(JidoActionTest.Fixtures.Actions.Add)
Code.ensure_compiled!(JidoActionTest.Fixtures.Actions.Multiply)

defmodule JidoActionTest.Fixtures.ChildIterator do
  @moduledoc false
  use Jido.Flow, name: "child_iterator"

  flow do
    iterate "child" do
      state(Zoi.map(), initial: %{count: 0})
      action(JidoActionTest.Fixtures.Increment)
      params(%{count: state(:count), index: iteration_index()})
      update(%{count: body_result(:count)})
      repeat(1)
    end

    output(result("child"))
  end
end

defmodule JidoActionTest.Fixtures.NestedFlow do
  @moduledoc false
  use Jido.Flow, name: "nested_fixture_flow"

  flow do
    step("add",
      action: JidoActionTest.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    output(result("add"))
  end
end

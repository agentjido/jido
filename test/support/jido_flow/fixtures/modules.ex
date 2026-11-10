Enum.each(
  [
    Jido.Test.Action.Fixtures.ConcurrencyProbeAction,
    Jido.Test.Exec.Fixtures.Transforms,
    Jido.Test.Action.Fixtures.Actions.Add,
    Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
    Jido.Test.Action.Fixtures.Actions.ErrorAction,
    Jido.Test.Action.Fixtures.Actions.KillingAction,
    Jido.Test.Action.Fixtures.Actions.Multiply,
    Jido.Test.Action.Fixtures.Actions.OutputEnvelopeAction
  ],
  &Code.ensure_compiled!/1
)

Code.ensure_compiled!(Jido.Test.Exec.Fixtures.Execution.BlockingAction)

defmodule Jido.Test.Flow.Fixtures.CountedValidationFlow do
  @moduledoc false
  use Jido.Flow,
    name: "counted_validation_flow",
    schema:
      Jido.Joi.map()
      |> Jido.Joi.transform({Jido.Test.Exec.Fixtures.Transforms, :count, [:input]}),
    output_schema:
      Jido.Joi.map()
      |> Jido.Joi.transform({Jido.Test.Exec.Fixtures.Transforms, :count, [:output]})

  flow do
    step("echo",
      action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value), input_passes: input(:input_passes)}
    )

    output(result("echo"))
  end
end

defmodule Jido.Test.Flow.Fixtures.ScalarTransformedOutputFlow do
  @moduledoc false
  use Jido.Flow,
    name: "scalar_transformed_output_flow",
    output_schema:
      Jido.Joi.map()
      |> Jido.Joi.transform({Jido.Test.Exec.Fixtures.Transforms, :count, [:invalid_output]})

  flow do
    step("echo",
      action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(result("echo"))
  end
end

defmodule Jido.Test.Flow.Fixtures.ScalarTransformedInputFlow do
  @moduledoc false
  use Jido.Flow,
    name: "scalar_transformed_input_flow",
    schema:
      Jido.Joi.map()
      |> Jido.Joi.transform({Jido.Test.Exec.Fixtures.Transforms, :count, [:invalid_input]})

  flow do
    step("echo",
      action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(result("echo"))
  end
end

defmodule Jido.Test.Flow.Fixtures.EnvelopeFlow do
  @moduledoc false
  use Jido.Flow,
    name: "envelope_flow",
    output_schema:
      Jido.Joi.map()
      |> Jido.Joi.transform({Jido.Test.Exec.Fixtures.Transforms, :count, [:envelope_output]})

  flow do
    step("envelope",
      action: Jido.Test.Action.Fixtures.Actions.OutputEnvelopeAction,
      params: %{value: input(:value)}
    )

    output(result("envelope"))
  end
end

defmodule Jido.Test.Flow.Fixtures.ScalarResultFlow do
  @moduledoc false
  use Jido.Flow, name: "scalar_result_flow"

  flow do
    step("echo",
      action: Jido.Test.Action.Fixtures.Actions.EchoParamsAction,
      params: %{value: input(:value)}
    )

    output(select(result("echo"), [:value]))
  end
end

defmodule Jido.Test.Flow.Fixtures.MathFlow do
  @moduledoc false
  use Jido.Flow,
    name: "math_flow",
    description: "Adds one and doubles the result"

  flow do
    step("add_one",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    step("double",
      action: Jido.Test.Action.Fixtures.Actions.Multiply,
      params: %{value: select(result("add_one"), [:value]), amount: 2}
    )

    output(result("double"))
  end
end

defmodule Jido.Test.Flow.Fixtures.AsyncMathFlow do
  @moduledoc false
  use Jido.Flow,
    name: "async_math_flow",
    description: "Runs through Exec options"

  flow do
    step("add_one",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    output(result("add_one"))
  end
end

defmodule Jido.Test.Flow.Fixtures.BlockingFlow do
  @moduledoc false
  use Jido.Flow, name: "blocking_flow"

  flow do
    step("blocking",
      action: Jido.Test.Exec.Fixtures.Execution.BlockingAction,
      params: %{value: input(:value)}
    )

    output(result("blocking"))
  end
end

defmodule Jido.Test.Flow.Fixtures.KillingFlow do
  @moduledoc false
  use Jido.Flow, name: "killing_flow"

  flow do
    step("kill", action: Jido.Test.Action.Fixtures.Actions.KillingAction, params: %{})
    output(result("kill"))
  end
end

defmodule Jido.Test.Flow.Fixtures.ChoicePublicPaths do
  @moduledoc false
  use Jido.Flow, name: "choice_public_paths"

  alias Jido.Test.Action.Fixtures.Actions.Add

  flow do
    choice "route" do
      option "priority" do
        condition(input(:kind) == :priority)
        action(Jido.Test.Action.Fixtures.Actions.Add)
        params(%{value: input(:value), amount: 1})
      end

      otherwise action: Add, params: %{value: input(:value), amount: 2}
    end

    output(result("route"))
  end
end

defmodule Jido.Test.Flow.Fixtures.TelemetryChildFlow do
  @moduledoc false
  use Jido.Flow, name: "telemetry_child_flow"

  flow do
    step("child_add",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value)}
    )

    output(result("child_add"))
  end
end

Code.ensure_compiled!(Jido.Test.Flow.Fixtures.TelemetryChildFlow)

defmodule Jido.Test.Flow.Fixtures.TelemetryParentFlow do
  @moduledoc false
  use Jido.Flow, name: "telemetry_parent_flow"

  flow do
    step("child",
      action: Jido.Test.Flow.Fixtures.TelemetryChildFlow,
      params: %{value: input(:value)}
    )

    output(result("child"))
  end
end

Code.ensure_compiled!(Jido.Test.Action.Fixtures.Increment)
Code.ensure_compiled!(Jido.Test.Action.Fixtures.Actions.Add)
Code.ensure_compiled!(Jido.Test.Action.Fixtures.Actions.Multiply)

defmodule Jido.Test.Flow.Fixtures.ChildIterator do
  @moduledoc false
  use Jido.Flow, name: "child_iterator"

  flow do
    iterate "child" do
      state(Jido.Joi.map(), initial: %{count: 0})
      action(Jido.Test.Action.Fixtures.Increment)
      params(%{count: state(:count), index: iteration_index()})
      update(%{count: body_result(:count)})
      repeat(1)
    end

    output(result("child"))
  end
end

defmodule Jido.Test.Flow.Fixtures.NestedFlow do
  @moduledoc false
  use Jido.Flow, name: "nested_fixture_flow"

  flow do
    step("add",
      action: Jido.Test.Action.Fixtures.Actions.Add,
      params: %{value: input(:value), amount: 1}
    )

    output(result("add"))
  end
end

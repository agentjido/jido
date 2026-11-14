defmodule Jido.Agent.DirectiveErrorsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Error.ValidationError
  alias Jido.Plugin.Audit
  alias Jido.Plugin.Timer
  alias Jido.Plugin.SensorManager

  defmodule SchemaEffect do
    @moduledoc false
    use Jido.Agent.Directive

    @schema Jido.Joi.struct(__MODULE__, %{name: Jido.Joi.string() |> Jido.Joi.min(1)}, coerce: true)
    @enforce_keys Jido.Joi.enforce_keys(@schema)
    defstruct Jido.Joi.struct_fields(@schema)

    def schema, do: @schema
  end

  defmodule RawIssuesEffect do
    @moduledoc false
    use Jido.Agent.Directive
    defstruct [:name]

    @impl true
    def validate(%__MODULE__{name: name}), do: Jido.Joi.parse(Jido.Joi.string(), name)
  end

  defmodule ReasonEffect do
    @moduledoc false
    use Jido.Agent.Directive
    defstruct []

    @impl true
    def validate(%__MODULE__{}), do: {:error, :custom_reason}
  end

  defp tick, do: Jido.Signal.new!("test.tick", %{}, source: "/test")

  defp assert_no_raw_issue(error) do
    refute inspect(error, limit: :infinity, structs: false) =~ "Zoi.Error"
  end

  test "a default schema failure is a Jido.Error with plain issues" do
    assert {:error, %ValidationError{code: :invalid_directive, details: %{issues: [issue]}} = error} =
             Directive.validate(%SchemaEffect{name: ""})

    assert %{code: :greater_than_or_equal_to, path: [:name], message: message} = issue
    assert is_binary(message)
    assert_no_raw_issue(error)
  end

  test "core Directive schema failures are Jido.Error values" do
    assert {:error, %ValidationError{code: :invalid_directive} = error} =
             Directive.validate(%Directive.Emit{signal: %{tick() | id: 1}})

    assert_no_raw_issue(error)
  end

  test "a custom validate/1 that returns raw issues is normalized" do
    assert {:error, %ValidationError{code: :invalid_directive} = error} =
             Directive.validate(%RawIssuesEffect{name: 1})

    assert_no_raw_issue(error)
  end

  test "a custom validate/1 keeps its own reason" do
    assert {:error, :custom_reason} = Directive.validate(%ReasonEffect{})
  end

  test "Timer validation returns Jido.Error values" do
    assert {:error, %ValidationError{code: :invalid_cron, details: %{reason: reason}}} =
             Directive.validate(Timer.cron("job", "nope", tick()))

    assert is_binary(reason)

    assert {:error, %ValidationError{code: :invalid_timezone}} =
             Directive.validate(Timer.cron("job", "* * * * *", tick(), timezone: "No/Zone"))

    assert {:error, %ValidationError{code: :invalid_job_id}} =
             Directive.validate(Timer.cron(self(), "* * * * *", tick()))

    assert {:error, %ValidationError{code: :invalid_job_id}} =
             Timer.Cancel.validate(%Timer.Cancel{job_id: self()})

    assert {:error, %ValidationError{code: :invalid_directive} = error} =
             Timer.Schedule.validate(%Timer.Schedule{delay_ms: -1, signal: tick()})

    assert_no_raw_issue(error)
  end

  test "Audit Record schema failures return Jido.Error values" do
    record = %{Audit.record("event", :accepted) | outcome: "not-atom"}

    assert {:error, %ValidationError{code: :invalid_directive} = error} = Audit.Record.validate(record)
    assert_no_raw_issue(error)
  end

  test "Sensor Manager schema failures return Jido.Error values" do
    assert {:error, %ValidationError{code: :invalid_directive} = error} =
             SensorManager.Start.validate(%SensorManager.Start{tag: :a, sensor: "bad", config: %{}})

    assert_no_raw_issue(error)
  end
end

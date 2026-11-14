defmodule Jido.Plugin.Timer.ApiTest do
  use Covenant.Case, component: "jido.plugin.timer", async: true

  import Jido.Test.PublicAPI

  alias Jido.Plugin.Timer
  alias Jido.Plugin.Timer.Signal.Tick

  alias Jido.Plugin.Timer.{
    Cancel,
    Cron,
    DeliveryAdapter,
    DSL,
    Every,
    Occurrence,
    Pause,
    Resume,
    Schedule
  }

  @tag obligation: [
         "jido.plugin.timer.I1",
         "jido.plugin.timer.I2",
         "jido.plugin.timer.I3",
         "jido.plugin.timer.I6"
       ]
  test "Timer exposes its durable delivery helpers and authoring API" do
    assert_public(Timer,
      api: [
        {:function, :cancel, 1},
        {:function, :cron, 4},
        {:function, :every, 4},
        {:function, :next_occurrence, 3},
        {:function, :occurrence_signal, 5},
        {:function, :pause, 1},
        {:function, :resume, 1},
        {:function, :schedule, 2}
      ],
      types: [{:type, :cron_option, 0}, {:type, :every_option, 0}, {:type, :option, 0}]
    )

    for module <- [Schedule, Cron, Every, Pause, Resume, Cancel] do
      assert_public(module, api: [{:function, :validate, 1}], types: [{:type, :t, 0}])
    end

    assert_public(Occurrence,
      api: [{:function, :from_signal, 1}, {:function, :schema, 0}],
      types: [{:type, :t, 0}]
    )

    assert_public(Tick,
      api: [
        {:function, :datacontenttype, 0},
        {:function, :dataschema, 0},
        {:function, :default_source, 0},
        {:function, :new, 2},
        {:function, :new!, 2},
        {:function, :schema, 0},
        {:function, :type, 0},
        {:function, :validate_data, 1}
      ],
      types: []
    )

    assert_public(DSL, api: [], types: [])

    assert_public(DeliveryAdapter,
      api: [],
      types: [
        {:type, :context, 0},
        {:type, :recurring_definition, 0},
        {:type, :recurring_definitions, 0}
      ]
    )

    for module <- [
          Timer.CronRules,
          Timer.DSL.Schedule,
          Timer.Runtime,
          Timer.WallClock
        ] do
      refute public_module?(module)
    end

    refute Code.ensure_loaded?(Timer.Agent)
    refute Code.ensure_loaded?(Timer.Server)
    refute function_exported?(Timer, :occurrence, 1)
  end

  defp assert_public(module, expected) do
    assert public_module?(module)
    assert documented_api(module) == Keyword.fetch!(expected, :api)
    assert documented_types(module) == Keyword.fetch!(expected, :types)
  end
end

defmodule Jido.Plugin.Scheduler.ApiTest do
  use Covenant.Case, component: "jido.plugin.scheduler", async: true

  import Jido.Test.PublicAPI

  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{Cancel, Cron, DeliveryAdapter, DSL, Occurrence, Schedule}

  @tag obligation: [
         "jido.plugin.scheduler.I1",
         "jido.plugin.scheduler.I2",
         "jido.plugin.scheduler.I3",
         "jido.plugin.scheduler.I6"
       ]
  test "Scheduler exposes its durable delivery helpers and authoring API" do
    assert_public(Scheduler,
      api: [
        {:function, :cancel, 1},
        {:function, :cron, 4},
        {:function, :next_occurrence, 3},
        {:function, :occurrence_signal, 5},
        {:function, :schedule, 2}
      ],
      types: [{:type, :cron_option, 0}, {:type, :option, 0}]
    )

    for module <- [Schedule, Cron, Cancel] do
      assert_public(module, api: [{:function, :validate, 1}], types: [{:type, :t, 0}])
    end

    assert_public(Occurrence,
      api: [{:function, :from_signal, 1}, {:function, :schema, 0}],
      types: [{:type, :t, 0}]
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
          Scheduler.CronRules,
          Scheduler.DSL.Schedule,
          Scheduler.Runtime,
          Scheduler.WallClock
        ] do
      refute public_module?(module)
    end

    refute Code.ensure_loaded?(Scheduler.Agent)
    refute Code.ensure_loaded?(Scheduler.Server)
    refute function_exported?(Scheduler, :occurrence, 1)
  end

  defp assert_public(module, expected) do
    assert public_module?(module)
    assert documented_api(module) == Keyword.fetch!(expected, :api)
    assert documented_types(module) == Keyword.fetch!(expected, :types)
  end
end

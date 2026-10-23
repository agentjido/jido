defmodule JidoTest.Contract.PluginSchedulerTest do
  use Covenant.Case, component: "jido.plugin.scheduler", async: true

  alias Jido.Agent
  alias Jido.Agent.Error
  alias Jido.Plugin.Scheduler
  alias Jido.Plugin.Scheduler.{DSL, Occurrence, WallClock}
  alias Jido.Plugin.Normalizer
  alias Jido.Signal
  alias JidoTest.AgentContract, as: F
  alias Spark.Dsl.{Entity, Extension, Section}

  @scope {ExampleJido, "agent-1", "tenant-1"}
  @instant ~U[2030-01-01 00:00:01Z]

  defp tick, do: Signal.new!("test.tick", %{value: 7}, source: "/test")

  defp contribution(data) do
    %{id: DSL.id(), provider: DSL, vsn: DSL.vsn(), data: data}
  end

  defp define(data, routes \\ []) do
    Agent.define(%{name: "scheduler-contract", routes: routes, extensions: [contribution(data)]})
  end

  defp action(type),
    do: %{
      path: type,
      handler: %{kind: :action, target: F.Return},
      state: %{source: :output, path: []}
    }

  @tag obligation: "jido.plugin.scheduler.I1"
  test "Scheduler state contains recurring definitions and applies changes in order" do
    assert Scheduler.sections() == []

    signal = tick()
    schedule = Scheduler.schedule(10, signal)
    cron = Scheduler.cron(:heartbeat, "* * * * *", signal, generation: 3)
    cancel = Scheduler.cancel(:heartbeat)

    assert [Scheduler.Schedule, Scheduler.Cron, Scheduler.Cancel] =
             Scheduler.Agent.directives([])

    assert {:ok, ^schedule} = Agent.Directive.validate(schedule)
    assert {:ok, cron} = Agent.Directive.validate(cron)
    assert {:ok, ^cancel} = Agent.Directive.validate(cancel)
    assert {:ok, _} = Agent.Directive.validate(Scheduler.schedule(0, signal))

    for generation <- [0, 2_147_483_647] do
      assert {:ok, _} =
               Agent.Directive.validate(
                 Scheduler.cron(:boundary, "* * * * *", signal, generation: generation)
               )
    end

    assert {:ok, unchanged} =
             Scheduler.Agent.apply_directives(%{cron: %{}}, [schedule])

    assert unchanged == %{cron: %{}}

    assert {:ok, %{cron: %{heartbeat: spec}}} =
             Scheduler.Agent.apply_directives(%{cron: %{}}, [cancel, cron])

    assert spec == %{
             cron_expression: "* * * * *",
             message: signal,
             timezone: "Etc/UTC",
             generation: 3
           }

    assert {:ok, %{cron: %{}}} =
             Scheduler.Agent.apply_directives(%{cron: %{}}, [cron, cancel])
  end

  @tag obligation: "jido.plugin.scheduler.I2"
  test "invalid and retired Scheduler inputs fail before state can change" do
    signal = tick()

    assert {:ok, "Etc/UTC"} = Scheduler.validate_cron_spec("* * * * *", signal, "")
    assert {:ok, "Etc/UTC"} = Scheduler.validate_cron_spec("* * * * * *", signal, nil)

    assert {:error, {:invalid_cron, :invalid_type}} =
             Scheduler.validate_cron_spec(nil, signal, nil)

    assert {:error, {:invalid_cron, _reason}} =
             Scheduler.validate_cron_spec("not cron", signal, nil)

    assert {:error, {:invalid_timezone, :invalid_type}} =
             Scheduler.validate_cron_spec("* * * * *", signal, 1)

    assert {:error, {:invalid_timezone, _reason}} =
             Scheduler.validate_cron_spec("* * * * *", signal, "No/SuchZone")

    for directive <- [
          Scheduler.schedule(-1, signal),
          Scheduler.schedule(1, :not_a_signal),
          Scheduler.cron(make_ref(), "* * * * *", signal),
          Scheduler.cron(:bad_cron, "not cron", signal),
          Scheduler.cron(:bad_zone, "* * * * *", signal, timezone: "No/SuchZone"),
          Scheduler.cron(:bad_generation, "* * * * *", signal, generation: -1),
          Scheduler.cron(:large_generation, "* * * * *", signal, generation: 2_147_483_648)
        ] do
      assert {:error, _reason} = Agent.Directive.validate(directive)
    end

    assert_raise ArgumentError, "Scheduler delivery is not supported", fn ->
      Scheduler.cron(:removed, "* * * * *", signal, delivery: :durable)
    end

    assert_raise ArgumentError, "Scheduler cron options must be a keyword list", fn ->
      apply(Scheduler, :cron, [:invalid_options, "* * * * *", signal, %{}])
    end

    assert_raise ArgumentError, "Scheduler cron does not accept options [:unknown]", fn ->
      Scheduler.cron(:invalid_options, "* * * * *", signal, unknown: true)
    end

    assert_raise ArgumentError, "Scheduler cron options must be unique", fn ->
      Scheduler.cron(:invalid_options, "* * * * *", signal,
        timezone: "Etc/UTC",
        timezone: "America/Chicago"
      )
    end

    for options <- [
          [delivery_interval: 100],
          [delivery_timeout: 5_000],
          [retry_delay_ms: 1, retry_delay_ms: 2],
          [timeout: 5_000]
        ] do
      assert {:error, %Jido.Error.ValidationError{}} =
               Normalizer.normalize_all([{Scheduler, options}])
    end

    refute function_exported?(Scheduler, :admit_occurrence, 2)
    refute function_exported?(Scheduler, :acknowledge, 1)

    for module <- [
          Scheduler.Acknowledge,
          Scheduler.Delivery,
          Scheduler.Durable,
          Scheduler.Enqueue,
          Scheduler.Queue,
          Scheduler.Signal.Enqueue
        ] do
      refute Code.ensure_loaded?(module)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I2"
  test "saved definitions with retired delivery fields fail validation" do
    {:scheduler, schema} = Scheduler.Agent.state_spec([])

    base = Scheduler.build_cron_spec("* * * * *", tick(), nil, 1)

    for generation <- [0, 2_147_483_647] do
      valid = Scheduler.build_cron_spec("* * * * *", tick(), nil, generation)
      assert {:ok, _state} = Zoi.parse(schema, %{cron: %{boundary: valid}})
    end

    for generation <- [-1, 2_147_483_648] do
      invalid = Scheduler.build_cron_spec("* * * * *", tick(), nil, generation)
      assert {:error, _errors} = Zoi.parse(schema, %{cron: %{boundary: invalid}})
    end

    for retired <- [
          %{delivery: :durable},
          %{pending: nil},
          %{last_scheduled_at: nil}
        ] do
      state = %{cron: %{old: Map.merge(base, retired)}}
      assert {:error, errors} = Zoi.parse(schema, state)
      assert Enum.any?(errors, &(&1.code == :unrecognized_key))
    end
  end

  @tag obligation: "jido.plugin.scheduler.I2"
  test "cron definitions reject nested nonportable values and reserved metadata" do
    port = Port.open({:spawn, "cat"}, [:binary])

    try do
      for value <- [self(), make_ref(), port, fn -> :ok end, [1 | :tail]] do
        assert {:error, {:invalid_job_id, :nonportable_term}} =
                 Agent.Directive.validate(
                   Scheduler.cron({:job, %{nested: value}}, "* * * * *", tick())
                 )

        invalid = %{tick() | data: %{nested: {:value, [value]}}}

        assert {:error, {:invalid_message, :nonportable_term}} =
                 Agent.Directive.validate(Scheduler.cron(:job, "* * * * *", invalid))

        assert {:error, :nonportable_occurrence_scope} =
                 Scheduler.validate_occurrence_scope({ExampleJido, "agent-1", [value]})
      end
    after
      Port.close(port)
    end

    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    assert {:error, :reserved_occurrence_metadata} =
             Agent.Directive.validate(Scheduler.cron("job-1", "* * * * *", tagged, generation: 1))
  end

  @tag obligation: "jido.plugin.scheduler.I3"
  test "static authoring normalizes timing and verifies accepted inputs" do
    assert [%Section{name: :schedules, entities: [%Entity{} = entity]}] = DSL.sections()
    assert entity.name == :schedule
    assert entity.target == DSL.Schedule
    assert entity.args == [:name]

    assert entity.schema == [
             name: [type: :atom, required: true],
             every: [type: :pos_integer],
             cron: [type: :string],
             timezone: [type: :string],
             signal: [type: :any, required: true]
           ]

    schedules = [
      %DSL.Schedule{
        name: :review,
        every: 60_000,
        signal: %{type: "work.request", data: %{}}
      },
      %DSL.Schedule{
        name: :refresh,
        cron: "*/5 * * * *",
        signal: %{type: "work.request", data: %{value: "refresh"}}
      }
    ]

    section = %{Extension.default_section_config() | entities: schedules}
    dsl = %{[:schedules] => section}

    assert {:ok, lowered} = DSL.lower(dsl, %{})

    assert lowered == %{
             schedules: [
               %{
                 name: :review,
                 timing: %{kind: :every, milliseconds: 60_000},
                 signal: %{type: "work.request", data: %{}}
               },
               %{
                 name: :refresh,
                 timing: %{
                   kind: :cron,
                   expression: "*/5 * * * *",
                   timezone: "Etc/UTC"
                 },
                 signal: %{type: "work.request", data: %{value: "refresh"}}
               }
             ]
           }

    assert {:ok, data} = DSL.normalize(lowered)
    assert {:ok, definition} = define(data, [action("work.request")])
    assert :ok = DSL.verify(data, definition)
    assert {:ok, ^data} = DSL.lower(%{}, data)
    assert {:error, %Error{code: :ambiguous_config}} = DSL.lower(dsl, data)
    assert {:ok, %{schedules: []}} = DSL.normalize(%{})

    assert {:ok, defaulted} =
             DSL.normalize(%{
               schedules: [
                 %{
                   name: :defaulted,
                   timing: %{kind: :cron, expression: "* * * * *"},
                   signal: %{type: "work.request"}
                 }
               ]
             })

    assert [defaulted_schedule] = defaulted.schedules
    assert defaulted_schedule.timing.timezone == "Etc/UTC"
    assert defaulted_schedule.signal.data == %{}

    for expression <- ["* * * * *", "* * * * * *", "* * * * * * *"] do
      assert {:ok, %{schedules: [%{timing: %{expression: ^expression}}]}} =
               DSL.normalize(%{
                 schedules: [
                   %{
                     name: :extended,
                     timing: %{kind: :cron, expression: expression},
                     signal: %{type: "work.request"}
                   }
                 ]
               })
    end

    [interval | _] = data.schedules

    assert {:error, %Error{code: :duplicate}} =
             DSL.normalize(%{schedules: [interval, interval]})

    assert {:error,
            %Error{
              code: :schedule_input,
              path: [:extensions, 0, 0, :schedules, :review],
              details: %{type: "work.request", definition: "scheduler-contract"}
            }} = define(data)
  end

  @tag obligation: "jido.plugin.scheduler.I3"
  test "static authoring rejects mixed timing and live Signal template data" do
    for schedule <- [
          %DSL.Schedule{name: :missing, signal: %{type: "work.request"}},
          %DSL.Schedule{
            name: :mixed,
            every: 1,
            cron: "* * * * *",
            signal: %{type: "work.request"}
          },
          %DSL.Schedule{
            name: :zoned_interval,
            every: 1,
            timezone: "Etc/UTC",
            signal: %{type: "work.request"}
          }
        ] do
      section = %{Extension.default_section_config() | entities: [schedule]}

      assert {:error, %Error{code: :schedule_timing}} =
               DSL.lower(%{[:schedules] => section}, %{})
    end

    base = %{
      name: :review,
      timing: %{kind: :every, milliseconds: 60_000},
      signal: %{type: "work.request", data: %{}}
    }

    assert {:error, %Error{code: :schedule_timing}} =
             DSL.normalize(%{schedules: [%{base | timing: :manual}]})

    for invalid <- [
          %{base | timing: %{kind: :every, milliseconds: 0}},
          %{base | timing: %{kind: :every, milliseconds: 1, timezone: "Etc/UTC"}},
          %{base | timing: %{expression: "* * * * *"}},
          %{base | timing: %{kind: :cron, expression: "not cron"}},
          %{base | timing: %{kind: :cron, expression: "* * * * *", timezone: "No/SuchZone"}},
          %{base | signal: %{type: "work.*"}},
          %{base | signal: %{type: "work.request", data: %{pid: self()}}}
        ] do
      assert {:error, %Error{}} = DSL.normalize(%{schedules: [invalid]})
    end
  end

  @tag obligation: "jido.plugin.scheduler.I6"
  test "equal occurrence coordinates produce one stable ID and preserve Signal values" do
    first = tick()
    second = tick()
    {:ok, first} = Signal.put_context(first, "customer", "acme")
    assert first.id != second.id

    assert {:ok, first} = Occurrence.attach(first, @scope, "job-1", 1, @instant)
    assert {:ok, second} = Occurrence.attach(second, @scope, "job-1", 1, @instant)
    assert {:ok, %Occurrence{} = occurrence} = Scheduler.occurrence(first)
    assert {:ok, ^occurrence} = Zoi.parse(Occurrence.schema(), Map.from_struct(occurrence))
    assert {:ok, ^occurrence} = Scheduler.occurrence(second)
    assert occurrence.id == "occ_JEa_q126OmcNwQorAlhQjtFbE93wjJ-qFlReVurgnHg"
    assert first.data == %{value: 7}
    assert Signal.get_context(first, "customer") == "acme"
    assert {:ok, restored} = first |> Signal.to_map() |> Signal.new()
    assert {:ok, ^occurrence} = Scheduler.occurrence(restored)
  end

  @tag obligation: "jido.plugin.scheduler.I6"
  test "every occurrence coordinate can change the logical ID" do
    coordinates = [
      {@scope, "job-1", 1, @instant},
      {{AnotherJido, "agent-1", "tenant-1"}, "job-1", 1, @instant},
      {{ExampleJido, "agent-2", "tenant-1"}, "job-1", 1, @instant},
      {{ExampleJido, "agent-1", "tenant-2"}, "job-1", 1, @instant},
      {@scope, "job-2", 1, @instant},
      {@scope, "job-1", 2, @instant},
      {@scope, "job-1", 1, DateTime.add(@instant, 1, :second)}
    ]

    ids =
      Enum.map(coordinates, fn {scope, job, generation, instant} ->
        {:ok, signal} = Occurrence.attach(tick(), scope, job, generation, instant)
        {:ok, occurrence} = Scheduler.occurrence(signal)
        occurrence.id
      end)

    assert length(Enum.uniq(ids)) == length(coordinates)
  end

  @tag obligation: "jido.plugin.scheduler.I6"
  test "missing, partial, and malformed occurrence metadata return errors" do
    assert {:error, :not_found} = Scheduler.occurrence(tick())
    {:ok, partial} = Signal.put_context(tick(), "jidooccurrenceid", "occ_partial")
    assert {:error, _} = Scheduler.occurrence(partial)
    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    {:ok, short_id} = Signal.put_context(tagged, "jidooccurrenceid", "x")
    assert {:ok, %Occurrence{id: "x"}} = Scheduler.occurrence(short_id)

    {:ok, empty_id} = Signal.put_context(tagged, "jidooccurrenceid", "")
    assert {:error, _reason} = Scheduler.occurrence(empty_id)

    for generation <- [0, 2_147_483_647] do
      {:ok, boundary} = Signal.put_context(tagged, "jidoschedulegen", generation)
      assert {:ok, %Occurrence{generation: ^generation}} = Scheduler.occurrence(boundary)
    end

    excessive = %{
      tagged
      | extensions: Map.put(tagged.extensions, "jidoschedulegen", 2_147_483_648)
    }

    assert {:error, _reason} = Scheduler.occurrence(excessive)

    for {key, value} <- [
          {"jidoschedulegen", -1},
          {"jidoschedulegen", "1"},
          {"jidoscheduledat", "not a timestamp"},
          {"jidoscheduledat", "2030-01-01T01:00:01+01:00"}
        ] do
      {:ok, invalid} = Signal.put_context(tagged, key, value)
      assert {:error, _} = Scheduler.occurrence(invalid)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I9"
  test "configuration accepts only bounded retry delays and valid time scales" do
    assert {:scheduler, _schema} = Scheduler.Agent.state_spec([])

    assert %{
             option_keys: %{
               agent_server: [:retry_delay_ms, :time_scale]
             }
           } = Scheduler.__jido_plugin__()

    for options <- [
          [],
          [retry_delay_ms: 1, time_scale: SchedEx.IdentityTimeScale],
          [retry_delay_ms: 4_294_967_295, time_scale: SchedEx.IdentityTimeScale]
        ] do
      assert :ok = Scheduler.validate_options(options)
      assert {:ok, [_spec]} = Normalizer.normalize_all([{Scheduler, options}])
    end

    for delay <- [0, -1, 1.5, :manual, 4_294_967_296] do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Scheduler retry_delay_ms is invalid",
                details: %{
                  option: :retry_delay_ms,
                  value: ^delay,
                  range: 1..4_294_967_295
                }
              }} = Scheduler.validate_options(retry_delay_ms: delay)
    end

    callbacks = SchedEx.TimeScale.behaviour_info(:callbacks)

    for time_scale <- [
          nil,
          String,
          __MODULE__.MissingTimeScale,
          __MODULE__.MissingNowTimeScale,
          __MODULE__.MissingSpeedupTimeScale
        ] do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Scheduler time_scale is invalid",
                details: %{
                  option: :time_scale,
                  value: ^time_scale,
                  callbacks: ^callbacks
                }
              }} = Scheduler.validate_options(time_scale: time_scale)
    end
  end

  @tag obligation: "jido.plugin.scheduler.I9"
  test "wall-clock waits round upward, recheck time, and permit cancellation" do
    slot = ~U[2030-01-01 00:00:01.000000Z]
    tag = make_ref()

    for time <- [
          ~U[2030-01-01 00:00:00.000000Z],
          ~U[2030-01-01 00:00:00.999500Z],
          slot
        ],
        do: send(self(), {tag, time})

    now = fn ->
      receive do
        {^tag, time} -> time
      after
        0 -> DateTime.add(slot, 1, :microsecond)
      end
    end

    wait = fn delay ->
      send(self(), {:wait, delay})
      :ok
    end

    assert :ok = WallClock.wait_until(slot, now, wait)
    assert_received {:wait, 1_000}
    assert_received {:wait, 1}

    Process.put(:scheduler_boundary_now, 0)

    boundary_now = fn ->
      case Process.get(:scheduler_boundary_now) do
        0 ->
          Process.put(:scheduler_boundary_now, 1)
          DateTime.add(slot, -1, :microsecond)

        1 ->
          Process.put(:scheduler_boundary_now, 2)
          slot

        _count ->
          DateTime.add(slot, 1, :microsecond)
      end
    end

    assert :ok = WallClock.wait_until(slot, boundary_now, wait)
    assert_received {:wait, 1}
    refute_received {:wait, 0}

    task =
      Task.async(fn -> WallClock.wait_until(DateTime.add(DateTime.utc_now(), 60, :second)) end)

    send(task.pid, :shutdown)
    assert :cancelled = Task.await(task)
  end

  defmodule MissingNowTimeScale do
    def speedup, do: 1
  end

  defmodule MissingSpeedupTimeScale do
    def now(_timezone), do: ~U[2030-01-01 00:00:00Z]
  end
end

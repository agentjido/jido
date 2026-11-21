defmodule Jido.Plugin.Timer.ContractTest do
  use Covenant.Case, component: "jido.plugin.timer", async: true

  alias Jido.Agent
  alias Jido.Error.ValidationError, as: Error
  alias Jido.Plugin.Timer
  alias Jido.Plugin.Timer.CronRules
  alias Jido.Plugin.Timer.{DSL, Occurrence, WallClock}
  alias Jido.Plugin.Normalizer
  alias Jido.Signal
  alias Jido.Test.Agent.Contract, as: F
  alias Spark.Dsl.{Entity, Extension, Section}

  @scope {ExampleJido, "agent-1", "tenant-1"}
  @instant ~U[2030-01-01 00:00:01Z]

  defmodule DeliveryAdapter do
    @behaviour Jido.Plugin.Timer.DeliveryAdapter

    @impl true
    def reconcile(_context, _desired), do: :ok

    @impl true
    def schedule(_context, _delay_ms, _signal), do: :ok
  end

  defp tick(type \\ "test.tick"), do: Signal.new!(type, %{value: 7}, source: "/test")

  defp reduce_state(state, directives),
    do: Timer.reduce(%{plugin_state: state, directives: directives}, [])

  defp contribution(data) do
    %{id: DSL.id(), provider: DSL, vsn: DSL.vsn(), data: data}
  end

  defp define(data, routes \\ []) do
    Agent.define(%{name: "timer-contract", routes: routes, plugins: [contribution(data)]})
  end

  defp action(type),
    do: %{
      path: type,
      handler: %{kind: :action, target: F.Return},
      state: %{source: :output, path: []}
    }

  @tag obligation: "jido.plugin.timer.I1"
  test "Timer state contains recurring definitions and applies changes in order" do
    assert Timer.sections() == []

    signal = tick()
    schedule = Timer.schedule(10, signal)
    cron = Timer.cron(:heartbeat, "* * * * *", signal, generation: 3)
    cancel = Timer.cancel(:heartbeat)

    assert [
             Timer.Schedule,
             Timer.Cron,
             Timer.Every,
             Timer.Pause,
             Timer.Resume,
             Timer.Cancel
           ] =
             Timer.directives([])

    assert {:ok, ^schedule} = Agent.Directive.validate(schedule)
    assert {:ok, cron} = Agent.Directive.validate(cron)
    assert {:ok, ^cancel} = Agent.Directive.validate(cancel)
    assert {:ok, _} = Agent.Directive.validate(Timer.schedule(0, signal))

    for generation <- [0, 2_147_483_647] do
      assert {:ok, _} =
               Agent.Directive.validate(Timer.cron(:boundary, "* * * * *", signal, generation: generation))
    end

    assert {:ok, unchanged} =
             reduce_state(%{cron: %{}}, [schedule])

    assert unchanged == %{cron: %{}, every: %{}}

    assert {:ok, %{cron: %{heartbeat: spec}, every: %{}}} =
             reduce_state(%{cron: %{}}, [cancel, cron])

    assert spec == %{
             cron_expression: "* * * * *",
             message: signal,
             timezone: "Etc/UTC",
             generation: 3
           }

    assert {:ok, %{cron: %{}, every: %{}}} =
             reduce_state(%{cron: %{}}, [cron, cancel])
  end

  @tag obligation: "jido.plugin.timer.I10"
  test "static interval options create one normal running interval definition" do
    assert %{
             option_keys: %{
               agent: [:interval, :signal_type, :signal_data, :source],
               agent_server: [:delivery_adapter, :retry_delay_ms, :time_scale]
             }
           } = Timer.__jido_plugin__()

    assert {:timer, empty_schema} = Timer.state_spec([])
    assert {:ok, %{cron: %{}, every: %{}}} = Jido.Joi.parse(empty_schema, nil)

    options = [
      interval: 25,
      signal_type: "system.heartbeat",
      signal_data: %{source: :clock},
      source: "urn:jido:clock"
    ]

    assert {:ok,
            %{
              interval: 25,
              signal_type: "system.heartbeat",
              signal_data: %{source: :clock},
              source: "urn:jido:clock"
            }} = Timer.static_configuration(options)

    assert {:timer, schema} = Timer.state_spec(options)
    assert {:ok, state} = Jido.Joi.parse(schema, nil)
    assert state.cron == %{}
    assert state.every.heartbeat.interval_ms == 25
    assert state.every.heartbeat.generation == 0
    assert state.every.heartbeat.status == :running
    assert state.every.heartbeat.message.type == "system.heartbeat"
    assert state.every.heartbeat.message.data == %{source: :clock}
    assert state.every.heartbeat.message.source == "urn:jido:clock"

    for options <- [
          [interval: 0],
          [signal_type: ""],
          [signal_data: []],
          [source: "not a URI reference"]
        ] do
      assert {:error, %Jido.Error.ValidationError{message: "Timer static interval options are invalid"}} =
               Timer.state_spec(options)
    end
  end

  @tag obligation: "jido.plugin.timer.I1"
  test "interval definitions replace by job ID and pause, resume, and cancel in order" do
    first = Timer.every(:review, 25, tick())
    replacement = Timer.every(:review, 50, tick("test.replaced"))

    assert {:ok, first} = Agent.Directive.validate(first)
    assert {:ok, replacement} = Agent.Directive.validate(replacement)
    assert {:ok, _pause} = Agent.Directive.validate(Timer.pause(:review))
    assert {:ok, _resume} = Agent.Directive.validate(Timer.resume(:review))

    assert {:ok, started} = reduce_state(%{cron: %{}}, [first])
    assert started.every.review.interval_ms == 25
    assert started.every.review.generation == 0
    assert started.every.review.status == :running

    assert {:ok, paused} = reduce_state(started, [Timer.pause(:review)])
    assert paused.every.review.status == :paused

    assert {:ok, resumed} = reduce_state(paused, [Timer.resume(:review)])
    assert resumed.every.review.generation == 1
    assert resumed.every.review.status == :running

    assert {:ok, replaced} = reduce_state(resumed, [replacement])
    assert replaced.every.review.interval_ms == 50
    assert replaced.every.review.generation == 2
    assert replaced.cron == %{}

    cron = Timer.cron(:review, "* * * * *", tick())
    assert {:ok, cron_state} = reduce_state(replaced, [cron])
    assert Map.has_key?(cron_state.cron, :review)
    assert cron_state.every == %{}
    assert {:ok, ^cron_state} = reduce_state(cron_state, [Timer.pause(:review)])
    assert {:ok, ^cron_state} = reduce_state(cron_state, [Timer.resume(:review)])

    assert {:ok, cancelled} = reduce_state(cron_state, [Timer.cancel(:review)])
    assert cancelled == %{cron: %{}, every: %{}}
  end

  @tag obligation: "jido.plugin.timer.I1"
  test "status reports missing definitions without a runtime" do
    for state <- [%{}, %{timer: %{cron: %{}, every: %{}}}, %{timer: %{cron: %{}}}] do
      assert Timer.status(state, :missing) == {:error, :not_found}
    end

    {:ok, timer} = reduce_state(%{cron: %{}}, [Timer.every(:review, 25, tick())])
    state = %{timer: timer, unrelated: %{value: 7}}
    assert Timer.status(state, :missing) == {:error, :not_found}
    assert {:ok, %{kind: :every, status: :active, generation: 0}} = Timer.status(state, :review)
    assert state == %{timer: timer, unrelated: %{value: 7}}
  end

  @tag obligation: "jido.plugin.timer.I1"
  test "status follows interval lifecycle and replacement between recurring kinds" do
    job_id = {:review, "tenant-1"}
    {:ok, started} = reduce_state(%{cron: %{}}, [Timer.every(job_id, 25, tick())])
    {:ok, paused} = reduce_state(started, [Timer.pause(job_id)])

    assert {:ok, %{kind: :every, status: :paused, generation: 0}} =
             Timer.status(%{timer: paused}, job_id)

    {:ok, resumed} = reduce_state(paused, [Timer.resume(job_id)])

    assert {:ok, %{kind: :every, status: :active, generation: 1}} =
             Timer.status(%{timer: resumed}, job_id)

    {:ok, replaced} = reduce_state(resumed, [Timer.every(job_id, 50, tick())])

    assert {:ok, %{kind: :every, status: :active, generation: 2}} =
             Timer.status(%{timer: replaced}, job_id)

    {:ok, cron} = reduce_state(replaced, [Timer.cron(job_id, "* * * * *", tick(), generation: 7)])

    assert {:ok, %{kind: :cron, status: :active, generation: 7}} =
             Timer.status(%{timer: cron}, job_id)

    {:ok, interval} = reduce_state(cron, [Timer.every(job_id, 25, tick())])

    assert {:ok, %{kind: :every, status: :active, generation: 8}} =
             Timer.status(%{timer: interval}, job_id)

    for timer <- [cron, interval] do
      {:ok, cancelled} = reduce_state(timer, [Timer.cancel(job_id)])
      assert Timer.status(%{timer: cancelled}, job_id) == {:error, :not_found}
    end
  end

  @tag obligation: "jido.plugin.timer.I1"
  test "status preserves absent cron generations and reports dormant definitions as active" do
    # This finite expression has no slot after the fixed boundary.
    expression = "0 0 0 1 1 * 2020"
    assert {:error, _} = Timer.next_occurrence(expression, "Etc/UTC", @instant)
    {:ok, timer} = reduce_state(%{cron: %{}}, [Timer.cron(:past, expression, tick())])

    assert {:ok, %{kind: :cron, status: :active, generation: nil}} =
             Timer.status(%{timer: timer}, :past)
  end

  @tag obligation: "jido.plugin.timer.I10"
  test "status reads the static heartbeat interval" do
    {:timer, schema} = Timer.state_spec(interval: 25)
    {:ok, timer} = Jido.Joi.parse(schema, nil)

    assert {:ok, %{kind: :every, status: :active, generation: 0}} =
             Timer.status(%{timer: timer}, :heartbeat)
  end

  @tag obligation: "jido.plugin.timer.I2"
  test "invalid and retired Timer inputs fail before state can change" do
    signal = tick()

    assert {:ok, "Etc/UTC"} = CronRules.validate_spec("* * * * *", signal, "")
    assert {:ok, "Etc/UTC"} = CronRules.validate_spec("* * * * * *", signal, nil)

    assert {:error, {:invalid_cron, :invalid_type}} =
             CronRules.validate_spec(nil, signal, nil)

    assert {:error, {:invalid_cron, _reason}} =
             CronRules.validate_spec("not cron", signal, nil)

    assert {:error, {:invalid_timezone, :invalid_type}} =
             CronRules.validate_spec("* * * * *", signal, 1)

    assert {:error, {:invalid_timezone, _reason}} =
             CronRules.validate_spec("* * * * *", signal, "No/SuchZone")

    for directive <- [
          Timer.schedule(-1, signal),
          Timer.schedule(1, :not_a_signal),
          Timer.every(:zero, 0, signal),
          Timer.every(:large, 4_294_967_296, signal),
          Timer.every(make_ref(), 10, signal),
          Timer.every(:bad_signal, 10, :not_a_signal),
          Timer.every(:bad_generation, 10, signal, generation: -1),
          Timer.cron(make_ref(), "* * * * *", signal),
          Timer.cron(:bad_cron, "not cron", signal),
          Timer.cron(:bad_zone, "* * * * *", signal, timezone: "No/SuchZone"),
          Timer.cron(:bad_generation, "* * * * *", signal, generation: -1),
          Timer.cron(:large_generation, "* * * * *", signal, generation: 2_147_483_648)
        ] do
      assert {:error, _reason} = Agent.Directive.validate(directive)
    end

    assert_raise ArgumentError, "Timer delivery is not supported", fn ->
      Timer.cron(:removed, "* * * * *", signal, delivery: :durable)
    end

    assert_raise ArgumentError, "Timer cron options must be a keyword list", fn ->
      apply(Timer, :cron, [:invalid_options, "* * * * *", signal, %{}])
    end

    assert_raise ArgumentError, "Timer every options must be a keyword list", fn ->
      apply(Timer, :every, [:invalid_options, 10, signal, %{}])
    end

    assert_raise ArgumentError, "Timer every does not accept options [:unknown]", fn ->
      Timer.every(:invalid_options, 10, signal, unknown: true)
    end

    assert_raise ArgumentError, "Timer every options must be unique", fn ->
      Timer.every(:invalid_options, 10, signal, generation: 1, generation: 2)
    end

    assert_raise ArgumentError, "Timer cron does not accept options [:unknown]", fn ->
      Timer.cron(:invalid_options, "* * * * *", signal, unknown: true)
    end

    assert_raise ArgumentError, "Timer cron options must be unique", fn ->
      Timer.cron(:invalid_options, "* * * * *", signal,
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
               Normalizer.normalize_all([{Timer, options}])
    end

    refute function_exported?(Timer, :admit_occurrence, 2)
    refute function_exported?(Timer, :acknowledge, 1)

    for module <- [
          Timer.Acknowledge,
          Timer.Delivery,
          Timer.Durable,
          Timer.Enqueue,
          Timer.Queue,
          Timer.Signal.Enqueue
        ] do
      refute Code.ensure_loaded?(module)
    end
  end

  @tag obligation: "jido.plugin.timer.I2"
  test "saved definitions with retired delivery fields fail validation" do
    {:timer, schema} = Timer.state_spec([])

    assert {:ok, %{cron: %{}, every: %{}}} =
             Jido.Joi.parse(schema, %{cron: %{}})

    base = CronRules.build_spec("* * * * *", tick(), nil, 1)

    for generation <- [0, 2_147_483_647] do
      valid = CronRules.build_spec("* * * * *", tick(), nil, generation)
      assert {:ok, _state} = Jido.Joi.parse(schema, %{cron: %{boundary: valid}})
    end

    for generation <- [-1, 2_147_483_648] do
      invalid = CronRules.build_spec("* * * * *", tick(), nil, generation)
      assert {:error, _errors} = Jido.Joi.parse(schema, %{cron: %{boundary: invalid}})
    end

    for retired <- [
          %{delivery: :durable},
          %{pending: nil},
          %{last_scheduled_at: nil}
        ] do
      state = %{cron: %{old: Map.merge(base, retired)}}
      assert {:error, errors} = Jido.Joi.parse(schema, state)
      assert Enum.any?(errors, &(&1.code == :unrecognized_key))
    end
  end

  @tag obligation: "jido.plugin.timer.I2"
  test "cron definitions reject nested nonportable values and reserved metadata" do
    port = Port.open({:spawn, "cat"}, [:binary])

    try do
      for value <- [self(), make_ref(), port, fn -> :ok end, [1 | :tail]] do
        assert {:error, %Jido.Error.ValidationError{code: :invalid_job_id, details: %{reason: :nonportable_term}}} =
                 Agent.Directive.validate(Timer.cron({:job, %{nested: value}}, "* * * * *", tick()))

        invalid = %{tick() | data: %{nested: {:value, [value]}}}

        assert {:error, %Jido.Error.ValidationError{code: :invalid_message, details: %{reason: :nonportable_term}}} =
                 Agent.Directive.validate(Timer.cron(:job, "* * * * *", invalid))

        assert {:error, :nonportable_occurrence_scope} =
                 CronRules.validate_occurrence_scope({ExampleJido, "agent-1", [value]})
      end
    after
      Port.close(port)
    end

    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    assert {:error, %Jido.Error.ValidationError{code: :reserved_occurrence_metadata}} =
             Agent.Directive.validate(Timer.cron("job-1", "* * * * *", tagged, generation: 1))
  end

  @tag obligation: "jido.plugin.timer.I3"
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
              path: [:plugins, 0, 0, :schedules, :review],
              details: %{type: "work.request", definition: "timer-contract"}
            }} = define(data)
  end

  @tag obligation: "jido.plugin.timer.I3"
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

  @tag obligation: "jido.plugin.timer.I6"
  test "equal occurrence coordinates produce one stable ID and preserve Signal values" do
    first = tick()
    second = tick()
    {:ok, first} = Signal.put_context(first, "customer", "acme")
    assert first.id != second.id

    assert {:ok, first} = Occurrence.attach(first, @scope, "job-1", 1, @instant)
    assert {:ok, second} = Occurrence.attach(second, @scope, "job-1", 1, @instant)
    assert {:ok, %Occurrence{} = occurrence} = Occurrence.from_signal(first)
    assert {:ok, ^occurrence} = Jido.Joi.parse(Occurrence.schema(), Map.from_struct(occurrence))
    assert {:ok, ^occurrence} = Occurrence.from_signal(second)
    assert occurrence.id == "occ_JEa_q126OmcNwQorAlhQjtFbE93wjJ-qFlReVurgnHg"
    assert first.data == %{value: 7}
    assert Signal.get_context(first, "customer") == "acme"
    assert {:ok, restored} = first |> Jido.Signal.Codec.to_map() |> Signal.new()
    assert {:ok, ^occurrence} = Occurrence.from_signal(restored)
  end

  @tag obligation: "jido.plugin.timer.I6"
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
        {:ok, occurrence} = Occurrence.from_signal(signal)
        occurrence.id
      end)

    assert length(Enum.uniq(ids)) == length(coordinates)
  end

  @tag obligation: "jido.plugin.timer.I6"
  test "missing, partial, and malformed occurrence metadata return errors" do
    assert {:error, :not_found} = Occurrence.from_signal(tick())
    {:ok, partial} = Signal.put_context(tick(), "jidooccurrenceid", "occ_partial")
    assert {:error, _} = Occurrence.from_signal(partial)
    {:ok, tagged} = Occurrence.attach(tick(), @scope, "job-1", 1, @instant)

    {:ok, short_id} = Signal.put_context(tagged, "jidooccurrenceid", "x")
    assert {:ok, %Occurrence{id: "x"}} = Occurrence.from_signal(short_id)

    {:ok, empty_id} = Signal.put_context(tagged, "jidooccurrenceid", "")
    assert {:error, _reason} = Occurrence.from_signal(empty_id)

    for generation <- [0, 2_147_483_647] do
      {:ok, boundary} = Signal.put_context(tagged, "jidoschedulegen", generation)
      assert {:ok, %Occurrence{generation: ^generation}} = Occurrence.from_signal(boundary)
    end

    excessive = %{
      tagged
      | extensions: Map.put(tagged.extensions, "jidoschedulegen", 2_147_483_648)
    }

    assert {:error, _reason} = Occurrence.from_signal(excessive)

    for {key, value} <- [
          {"jidoschedulegen", -1},
          {"jidoschedulegen", "1"},
          {"jidoscheduledat", "not a timestamp"},
          {"jidoscheduledat", "2030-01-01T01:00:01+01:00"}
        ] do
      {:ok, invalid} = Signal.put_context(tagged, key, value)
      assert {:error, _} = Occurrence.from_signal(invalid)
    end
  end

  @tag obligation: "jido.plugin.timer.I9"
  test "configuration accepts only bounded retry delays and valid time scales" do
    assert {:timer, _schema} = Timer.state_spec([])

    assert %{
             option_keys: %{
               agent_server: [:delivery_adapter, :retry_delay_ms, :time_scale]
             }
           } = Timer.__jido_plugin__()

    for options <- [
          [],
          [delivery_adapter: DeliveryAdapter],
          [retry_delay_ms: 1, time_scale: SchedEx.IdentityTimeScale],
          [retry_delay_ms: 4_294_967_295, time_scale: SchedEx.IdentityTimeScale]
        ] do
      assert :ok = Timer.validate_options(options)
      assert {:ok, [_spec]} = Normalizer.normalize_all([{Timer, options}])
    end

    for delay <- [0, -1, 1.5, :manual, 4_294_967_296] do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Timer retry_delay_ms is invalid",
                details: %{
                  option: :retry_delay_ms,
                  value: ^delay,
                  range: 1..4_294_967_295
                }
              }} = Timer.validate_options(retry_delay_ms: delay)
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
                message: "Timer time_scale is invalid",
                details: %{
                  option: :time_scale,
                  value: ^time_scale,
                  callbacks: ^callbacks
                }
              }} = Timer.validate_options(time_scale: time_scale)
    end

    for adapter <- [nil, String, __MODULE__.MissingDeliveryAdapter] do
      assert {:error,
              %Jido.Error.ValidationError{
                message: "Timer delivery_adapter is invalid",
                details: %{
                  option: :delivery_adapter,
                  value: ^adapter,
                  callbacks: [reconcile: 2, schedule: 3]
                }
              }} = Timer.validate_options(delivery_adapter: adapter)
    end
  end

  @tag obligation: "jido.plugin.timer.I6"
  test "cron rules and occurrence identity are available to durable hosts" do
    assert {:ok, ~U[2030-01-01 00:00:01Z]} =
             Timer.next_occurrence("* * * * * * *", "Etc/UTC", ~U[2030-01-01 00:00:00Z])

    assert {:ok, ~U[2030-01-01 00:00:02Z]} =
             Timer.next_occurrence(
               "* * * * * * *",
               "Etc/UTC",
               ~U[2030-01-01 00:00:01.000001Z]
             )

    assert {:error, _reason} =
             Timer.next_occurrence("not cron", "Etc/UTC", ~U[2030-01-01 00:00:00Z])

    assert {:error, :invalid_cron_boundary} =
             Timer.next_occurrence("@reboot", "Etc/UTC", ~U[2030-01-01 00:00:00Z])

    assert {:error, :invalid_cron_boundary} =
             Timer.next_occurrence("* * * * *", "Etc/UTC", :not_a_datetime)

    assert {:ok, first} =
             Timer.occurrence_signal(
               tick(),
               {ExampleJido, "agent-1", nil},
               "job-1",
               3,
               ~U[2030-01-01 00:00:01Z]
             )

    assert {:ok, second} =
             Timer.occurrence_signal(
               tick(),
               {ExampleJido, "agent-1", nil},
               "job-1",
               3,
               ~U[2030-01-01 00:00:01Z]
             )

    assert {:ok, first_occurrence} = Occurrence.from_signal(first)
    assert {:ok, second_occurrence} = Occurrence.from_signal(second)
    assert first_occurrence.id == second_occurrence.id
    refute first.id == second.id

    assert {:ok, default_generation} =
             Timer.occurrence_signal(
               tick(),
               {ExampleJido, "agent-1", nil},
               "legacy-job",
               nil,
               ~U[2030-01-01 00:00:01Z]
             )

    assert {:ok, %Occurrence{generation: 0}} = Occurrence.from_signal(default_generation)

    for invalid_generation <- [-1, 2_147_483_648, "3"] do
      assert {:error, :invalid_schedule_occurrence} =
               Timer.occurrence_signal(
                 tick(),
                 {ExampleJido, "agent-1", nil},
                 "job-1",
                 invalid_generation,
                 ~U[2030-01-01 00:00:01Z]
               )
    end

    {:ok, reserved} = Signal.put_context(tick(), "jidooccurrenceid", "reserved")

    assert {:error, :reserved_occurrence_metadata} =
             Timer.occurrence_signal(
               reserved,
               {ExampleJido, "agent-1", nil},
               "job-1",
               3,
               ~U[2030-01-01 00:00:01Z]
             )
  end

  @tag obligation: "jido.plugin.timer.I9"
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

    Process.put(:timer_boundary_now, 0)

    boundary_now = fn ->
      case Process.get(:timer_boundary_now) do
        0 ->
          Process.put(:timer_boundary_now, 1)
          DateTime.add(slot, -1, :microsecond)

        1 ->
          Process.put(:timer_boundary_now, 2)
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

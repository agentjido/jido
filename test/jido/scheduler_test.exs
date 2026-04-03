defmodule JidoTest.SchedulerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import JidoTest.Eventually

  alias Jido.Scheduler
  alias Jido.Scheduler.Job
  alias JidoTest.Support.FailingTimeZoneDatabase

  setup do
    original_database = Calendar.get_time_zone_database()

    on_exit(fn ->
      Calendar.put_time_zone_database(original_database)
    end)

    :ok
  end

  defmodule TestModule do
    def test_func(arg) do
      send(arg, :test_func_called)
    end
  end

  defp time_zone_database do
    Application.get_env(:jido, :time_zone_database, TimeZoneInfo.TimeZoneDatabase)
  end

  describe "run_every/5 with module/function/args" do
    test "starts a cron job with module, function, and args" do
      assert {:ok, pid} = Scheduler.run_every(TestModule, :test_func, [self()], "* * * * *")
      assert is_pid(pid)
      assert Process.alive?(pid)
      Scheduler.cancel(pid)
    end

    test "accepts timezone option" do
      assert {:ok, pid} =
               Scheduler.run_every(TestModule, :test_func, [self()], "* * * * *",
                 timezone: "Etc/UTC"
               )

      assert is_pid(pid)
      Scheduler.cancel(pid)
    end

    test "returns {:error, reason} for invalid cron input" do
      assert {:error, {:invalid_cron, _reason}} =
               Scheduler.run_every(TestModule, :test_func, [self()], "not-a-cron")
    end

    test "returns {:error, reason} for invalid cron type" do
      assert {:error, {:invalid_cron, :invalid_type}} =
               Scheduler.run_every(TestModule, :test_func, [self()], 123)
    end

    test "returns {:error, reason} for invalid timezone input" do
      assert {:error, {:invalid_timezone, _reason}} =
               Scheduler.run_every(TestModule, :test_func, [self()], "* * * * *",
                 timezone: "Not/A_Zone"
               )
    end

    test "returns {:error, reason} for invalid timezone type" do
      assert {:error, {:invalid_timezone, :invalid_type}} =
               Scheduler.run_every(TestModule, :test_func, [self()], "* * * * *", timezone: 123)
    end
  end

  describe "run_every/3 with anonymous function" do
    test "starts a cron job with an anonymous function" do
      test_pid = self()
      fun = fn -> send(test_pid, :anon_func_called) end

      assert {:ok, pid} = Scheduler.run_every(fun, "* * * * *")
      assert is_pid(pid)
      assert Process.alive?(pid)
      Scheduler.cancel(pid)
    end

    test "accepts timezone option" do
      fun = fn -> :ok end
      assert {:ok, pid} = Scheduler.run_every(fun, "* * * * *", timezone: "Etc/UTC")
      assert is_pid(pid)
      Scheduler.cancel(pid)
    end

    test "returns {:error, reason} for invalid cron input without crashing caller" do
      fun = fn -> :ok end

      assert {:error, {:invalid_cron, _reason}} =
               Scheduler.run_every(fun, "not-a-cron-expression")
    end

    test "returns error for invalid timezone identifier without crashing caller" do
      fun = fn -> :ok end

      assert {:error, {:invalid_timezone, _}} =
               Scheduler.run_every(fun, "* * * * *", timezone: "Invalid/Nowhere")
    end

    test "returns error for invalid timezone option type" do
      fun = fn -> :ok end

      assert {:error, {:invalid_timezone, :invalid_type}} =
               Scheduler.run_every(fun, "* * * * *", timezone: :america_chicago)
    end

    test "uses configured time zone database without mutating the global calendar database" do
      Calendar.put_time_zone_database(Calendar.UTCOnlyTimeZoneDatabase)

      assert {:ok, pid} =
               Scheduler.run_every(fn -> :ok end, "* * * * *", timezone: "America/New_York")

      assert Calendar.get_time_zone_database() == Calendar.UTCOnlyTimeZoneDatabase
      Scheduler.cancel(pid)
    end

    test "executes callbacks in an isolated worker process" do
      test_pid = self()

      assert {:ok, pid} =
               Scheduler.run_every(
                 fn -> send(test_pid, {:worker_tick, self()}) end,
                 "* * * * * * *"
               )

      assert_receive {:worker_tick, worker_pid}, 2_000
      assert is_pid(worker_pid)
      refute worker_pid == pid
      Scheduler.cancel(pid)
    end
  end

  describe "cancel/1" do
    test "cancels a running cron job" do
      {:ok, pid} = Scheduler.run_every(fn -> :ok end, "* * * * *")
      assert Process.alive?(pid)

      assert :ok = Scheduler.cancel(pid)
      eventually(fn -> not Process.alive?(pid) end)
    end

    test "cancels a blocked callback worker and stops future ticks" do
      test_pid = self()

      {:ok, pid} =
        Scheduler.run_every(
          fn ->
            send(test_pid, {:worker_started, self()})
            Process.sleep(:infinity)
          end,
          "* * * * * * *"
        )

      assert_receive {:worker_started, worker_pid}, 2_000
      assert is_pid(worker_pid)

      assert :ok = Scheduler.cancel(pid)
      eventually(fn -> not Process.alive?(pid) end)
      eventually(fn -> not Process.alive?(worker_pid) end)
      refute_receive {:worker_started, _another_worker}, 1_500
    end

    test "callback kill does not take down the owner" do
      test_pid = self()

      owner =
        spawn(fn ->
          {:ok, pid} =
            Scheduler.run_every(
              fn -> Process.exit(self(), :kill) end,
              "* * * * * * *"
            )

          send(test_pid, {:owner_started, self(), pid})

          receive do
            :stop -> Scheduler.cancel(pid)
          end
        end)

      ref = Process.monitor(owner)

      assert_receive {:owner_started, ^owner, pid}, 1_000
      assert Process.alive?(owner)
      assert Process.alive?(pid)

      refute_receive {:DOWN, ^ref, :process, ^owner, _reason}, 1_500
      assert Process.alive?(owner)

      send(owner, :stop)
      assert_receive {:DOWN, ^ref, :process, ^owner, _reason}, 2_000
    end
  end

  describe "alive?/1" do
    test "returns true for a running cron job" do
      {:ok, pid} = Scheduler.run_every(fn -> :ok end, "* * * * *")
      assert Scheduler.alive?(pid) == true
      Scheduler.cancel(pid)
    end

    test "returns false after cancellation" do
      {:ok, pid} = Scheduler.run_every(fn -> :ok end, "* * * * *")
      Scheduler.cancel(pid)
      eventually(fn -> Scheduler.alive?(pid) == false end)
    end

    test "returns false for a dead pid" do
      {:ok, pid} = Scheduler.run_every(fn -> :ok end, "* * * * *")
      Scheduler.cancel(pid)
      eventually(fn -> Scheduler.alive?(pid) == false end)
    end
  end

  describe "DST handling" do
    test "skips nonexistent spring-forward occurrences" do
      timezone = "America/Chicago"
      {:ok, schedule} = Job.prepare_schedule("30 2 * * *", timezone)

      {:ok, now} =
        DateTime.from_naive(~N[2026-03-08 00:30:00], timezone, time_zone_database())

      {:ok, expected} =
        DateTime.from_naive(~N[2026-03-09 02:30:00], timezone, time_zone_database())

      assert {:ok, ^expected} = Job.next_scheduled_at(schedule.cron, timezone, now)
    end

    test "chooses the later ambiguous fall-back occurrence" do
      timezone = "America/Chicago"
      {:ok, schedule} = Job.prepare_schedule("31 1 * * *", timezone)

      {:ambiguous, _first_now, now} =
        DateTime.from_naive(~N[2026-11-01 01:30:30], timezone, time_zone_database())

      {:ambiguous, _first_expected, expected} =
        DateTime.from_naive(~N[2026-11-01 01:31:00], timezone, time_zone_database())

      assert {:ok, ^expected} = Job.next_scheduled_at(schedule.cron, timezone, now)
      assert DateTime.diff(expected, now, :millisecond) == 30_000
    end
  end

  describe "runtime schedule recovery" do
    test "time zone database failure enters retry mode and resumes without killing the owner" do
      test_pid = self()
      tick_gate = {__MODULE__, make_ref()}
      owner_tag = make_ref()
      :persistent_term.put(tick_gate, false)

      # Ensure we start with a working database
      Application.put_env(:jido, :time_zone_database, TimeZoneInfo.TimeZoneDatabase)

      on_exit(fn ->
        :persistent_term.erase(tick_gate)
        Application.put_env(:jido, :time_zone_database, TimeZoneInfo.TimeZoneDatabase)
      end)

      capture_log(fn ->
        owner =
          spawn(fn ->
            {:ok, pid} =
              Scheduler.run_every(
                fn ->
                  if :persistent_term.get(tick_gate, false) do
                    send(test_pid, {:recovered_tick, owner_tag, self()})
                  end
                end,
                "* * * * * * *",
                timezone: "America/New_York"
              )

            send(test_pid, {:job_started, owner_tag, self(), pid})

            receive do
              :stop -> Scheduler.cancel(pid)
            end
          end)

        assert_receive {:job_started, ^owner_tag, ^owner, job_pid}, 1_000
        assert Process.alive?(owner)
        assert Process.alive?(job_pid)

        # Simulate database failure
        Application.put_env(:jido, :time_zone_database, FailingTimeZoneDatabase)

        eventually(fn -> Process.alive?(owner) and Process.alive?(job_pid) end, timeout: 2_000)

        # Restore working database
        :persistent_term.put(tick_gate, true)
        Application.put_env(:jido, :time_zone_database, TimeZoneInfo.TimeZoneDatabase)

        assert_receive {:recovered_tick, ^owner_tag, worker_pid}, 3_000
        assert is_pid(worker_pid)
        refute worker_pid == job_pid
        assert Process.alive?(job_pid)
        send(owner, :stop)
      end)
    end
  end
end

defmodule JidoTest.SchedulerTest do
  use ExUnit.Case, async: true

  import JidoTest.Eventually

  alias Jido.Scheduler

  defmodule TestModule do
    def test_func(arg) do
      send(arg, :test_func_called)
    end
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

    test "returns error for invalid cron expression without crashing caller" do
      fun = fn -> :ok end

      assert {:error, reason} = Scheduler.run_every(fun, "not-a-cron-expression")

      assert match?({:invalid_cron_expression, _}, reason) or
               match?({:invalid_cron, _}, reason)
    end

    test "returns error for invalid timezone identifier without crashing caller" do
      fun = fn -> :ok end

      assert {:error, {:invalid_timezone, _}} =
               Scheduler.run_every(fun, "* * * * *", timezone: "Invalid/Nowhere")
    end

    test "returns error for invalid timezone option type" do
      fun = fn -> :ok end

      assert {:error, :invalid_timezone} =
               Scheduler.run_every(fun, "* * * * *", timezone: :america_chicago)
    end
  end

  describe "cancel/1" do
    test "cancels a running cron job" do
      {:ok, pid} = Scheduler.run_every(fn -> :ok end, "* * * * *")
      assert Process.alive?(pid)

      assert :ok = Scheduler.cancel(pid)
      eventually(fn -> not Process.alive?(pid) end)
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
end

defmodule JidoTest.Agent.Directive.CronCancelTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Directive
  alias Jido.Agent.Directive.CronCancel
  alias Jido.AgentServer.DirectiveExec

  describe "CronCancel directive creation" do
    test "creates cron cancel directive with atom job_id" do
      directive = %CronCancel{job_id: :heartbeat}

      assert %CronCancel{} = directive
      assert directive.job_id == :heartbeat
    end

    test "creates cron cancel directive with string job_id" do
      directive = %CronCancel{job_id: "daily_cleanup"}

      assert directive.job_id == "daily_cleanup"
    end

    test "creates cron cancel directive with reference job_id" do
      ref = make_ref()
      directive = %CronCancel{job_id: ref}

      assert directive.job_id == ref
    end

    test "creates cron cancel directive with integer job_id" do
      directive = %CronCancel{job_id: 123}

      assert directive.job_id == 123
    end
  end

  describe "Directive.cron_cancel/1 helper" do
    test "creates cron cancel directive with atom" do
      directive = Directive.cron_cancel(:heartbeat)

      assert %CronCancel{} = directive
      assert directive.job_id == :heartbeat
    end

    test "creates cron cancel directive with string" do
      directive = Directive.cron_cancel("daily_cleanup")

      assert directive.job_id == "daily_cleanup"
    end

    test "creates cron cancel directive with reference" do
      ref = make_ref()
      directive = Directive.cron_cancel(ref)

      assert directive.job_id == ref
    end

    test "accepts any term as job_id" do
      test_ids = [
        :atom_id,
        "string_id",
        123,
        make_ref(),
        {:tuple, "id"},
        ["list", "id"]
      ]

      for id <- test_ids do
        directive = Directive.cron_cancel(id)
        assert %CronCancel{} = directive
        assert directive.job_id == id
      end
    end
  end

  describe "schema validation" do
    test "has valid schema" do
      assert is_struct(CronCancel.schema())
    end

    test "enforces required job_id key" do
      assert_raise ArgumentError, fn ->
        struct!(CronCancel, %{})
      end
    end

    test "allows valid struct creation" do
      directive = struct!(CronCancel, %{job_id: :test})
      assert directive.job_id == :test
    end
  end

  describe "directive execution" do
    test "removes persisted cron specs even when no runtime job exists" do
      directive = %CronCancel{job_id: :durable}

      state = %{
        id: "agent-1",
        cron_jobs: %{},
        cron_specs: %{
          durable: Jido.Scheduler.build_cron_spec("* * * * *", :tick, "America/New_York")
        }
      }

      assert {:ok, new_state} = DirectiveExec.exec(directive, nil, state)
      assert new_state.cron_jobs == %{}
      assert new_state.cron_specs == %{}
    end
  end
end

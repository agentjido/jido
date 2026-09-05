defmodule Jido.Plugin.ResultContractTest do
  use JidoTest.Case, async: true

  alias Jido.Agent.Command
  alias Jido.Plugin
  alias Jido.Plugin.{DirectiveContext, Spec}

  defmodule Agent do
    use Jido.Agent,
      name: "plugin_result_contract",
      schema: Zoi.object(%{count: Zoi.integer() |> Zoi.default(1)})
  end

  defmodule CallbackPlugin do
    use Jido.Plugin

    @impl true
    def prepare(command, opts), do: Keyword.fetch!(opts, :callback).(command)
    @impl true
    def admit(_runtime, command, opts), do: prepare(command, opts)
    @impl true
    def dispatch(_runtime, _directive, _context, opts), do: prepare(nil, opts)
    @impl true
    def await_ready(_runtime, opts), do: prepare(nil, opts)
  end

  for callback <- [:prepare, :admit] do
    test "#{callback} validates before it compares the Agent" do
      command = command()
      changed = %{command | agent: %{command.agent | id: "replacement"}, context: []}
      assert {:error, expected} = Command.validate(changed)

      assert {:error, actual} =
               run_command(unquote(callback), command, fn _ -> {:ok, changed} end)

      assert actual.message == expected.message
      assert actual.details == expected.details
    end

    test "#{callback} keeps numeric Agent equality and the returned value" do
      command = command()
      changed = %{command | agent: %{command.agent | state: %{count: 1.0}}}
      assert changed.agent == command.agent
      refute changed.agent === command.agent
      assert {:ok, actual} = run_command(unquote(callback), command, fn _ -> {:ok, changed} end)
      assert actual === changed
    end

    test "#{callback} keeps Agent replacement error details" do
      command = command()
      changed = %{command | agent: %{command.agent | id: "replacement"}}
      assert {:error, error} = run_command(unquote(callback), command, fn _ -> {:ok, changed} end)
      assert error.message == "Agent Plugin cannot replace the Agent"

      expected =
        if unquote(callback) == :admit,
          do: %{plugin: CallbackPlugin, callback: :admit},
          else: %{plugin: CallbackPlugin}

      assert error.details == expected
    end
  end

  for {callback, label, failure} <- [
        {:dispatch, "dispatch/4", "Agent Plugin Directive dispatch failed"},
        {:await_ready, "await_ready/2", "Agent Plugin readiness check failed"}
      ] do
    test "#{callback} keeps success, returned errors, and invalid result details" do
      for result <- [:ok, {:error, %{reason: :denied}}] do
        assert run_status(unquote(callback), fn _ -> result end) === result
      end

      assert {:error, error} = run_status(unquote(callback), fn _ -> {:ok, :unexpected} end)
      assert error.message == "Agent Plugin #{unquote(label)} returned an invalid result"
      assert error.details == %{plugin: CallbackPlugin, result: {:ok, :unexpected}}
    end

    test "#{callback} contains raised errors, throws, and exits" do
      assert {:error, error} = run_status(unquote(callback), fn _ -> raise "callback fault" end)
      assert error.message == unquote(failure)

      assert %{plugin: CallbackPlugin, error: %RuntimeError{message: "callback fault"}} =
               error.details

      for {kind, fun} <- [throw: fn _ -> throw(:fault) end, exit: fn _ -> exit(:fault) end] do
        assert {:error, error} = run_status(unquote(callback), fun)
        assert error.message == unquote(failure)
        assert error.details == %{plugin: CallbackPlugin, kind: kind, reason: :fault}
      end
    end
  end

  test "readiness does not invoke runtime-free or absent callbacks" do
    spec = spec(fn _ -> flunk("runtime-free readiness callback was invoked") end)
    assert :ok = Plugin.await_ready(%{spec | runtime?: false}, nil)
    assert :ok = Plugin.await_ready(%{spec | module: __MODULE__}, nil)
  end

  defp command do
    {:ok, command} =
      Command.new(Agent.new!(id: "original"), signal("test.input"))

    command
  end

  defp spec(fun), do: %Spec{module: CallbackPlugin, options: [callback: fun], runtime?: true}

  defp run_command(:prepare, command, fun) do
    case Plugin.prepare_specs(command, [spec(fun)]) do
      {:ok, prepared, _specs} -> {:ok, prepared}
      error -> error
    end
  end

  defp run_command(:admit, command, fun), do: Plugin.admit(command, [spec(fun)], %{})

  defp run_status(:dispatch, fun) do
    Plugin.dispatch(spec(fun), nil, :directive, struct(DirectiveContext))
  end

  defp run_status(:await_ready, fun), do: Plugin.await_ready(spec(fun), nil)
end

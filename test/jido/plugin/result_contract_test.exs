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
    def admit(_runtime, command, opts), do: Keyword.fetch!(opts, :callback).(command)
    @impl true
    def dispatch(_runtime, _directive, _context, opts), do: Keyword.fetch!(opts, :callback).(nil)
    @impl true
    def await_ready(_runtime, opts), do: Keyword.fetch!(opts, :callback).(nil)
  end

  for callback <- [:admit] do
    test "#{callback} validates before it compares the Agent" do
      command = command()
      changed = %{command | agent: %{command.agent | id: "replacement"}, context: []}
      assert {:error, expected} = Command.validate(changed)

      assert {:error, actual} =
               run_command(unquote(callback), command, fn _ -> {:ok, changed} end)

      assert actual.message == expected.message
      assert actual.details == expected.details
    end

    test "#{callback} validates numerically equal Agent state" do
      command = command()
      changed = %{command | agent: %{command.agent | state: %{count: 1.0}}}
      assert changed.agent == command.agent
      refute changed.agent === command.agent

      assert {:error, %Jido.Error.ValidationError{}} =
               run_command(unquote(callback), command, fn _ -> {:ok, changed} end)
    end

    test "#{callback} keeps Agent replacement error details" do
      command = command()
      changed = %{command | agent: %{command.agent | id: "replacement"}}
      assert {:error, error} = run_command(unquote(callback), command, fn _ -> {:ok, changed} end)
      assert error.message == "Agent Plugin cannot replace the Agent"

      expected = %{
        code: :plugin_invalid_callback_result,
        plugin: CallbackPlugin,
        callback: :admit
      }

      assert error.details == expected
    end
  end

  test "admit can change only its package-owned input" do
    command = command()

    assert {:ok, admitted} =
             run_command(:admit, command, fn current ->
               {:ok, Command.put_plugin_input(current, CallbackPlugin, %{value: self()})}
             end)

    assert admitted.plugin_inputs == %{CallbackPlugin => %{value: self()}}
  end

  test "admit cannot change the Signal, caller context, or a foreign input" do
    command = %{command() | plugin_inputs: %{__MODULE__ => :original}}

    changes = [
      {%{command | signal: %{command.signal | data: %{changed: true}}},
       "Agent Plugin cannot change the Signal"},
      {%{command | context: %{request: :changed}},
       "Agent Plugin cannot change the caller context"},
      {%{command | plugin_inputs: %{__MODULE__ => :changed}},
       "Agent Plugin cannot change another Plugin's input"}
    ]

    for {changed, message} <- changes do
      assert {:error, error} = run_command(:admit, command, fn _current -> {:ok, changed} end)
      assert error.message == message
      assert error.details.callback == :admit
      assert error.details.plugin == CallbackPlugin
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

      assert error.details == %{
               code: :plugin_invalid_callback_result,
               plugin: CallbackPlugin,
               result: {:ok, :unexpected}
             }
    end

    test "#{callback} contains raised errors, throws, and exits" do
      assert {:error, error} = run_status(unquote(callback), fn _ -> raise "callback fault" end)
      assert error.message == unquote(failure)

      assert %{
               code: :plugin_callback_failed,
               callback: unquote(callback),
               plugin: CallbackPlugin,
               error: %RuntimeError{message: "callback fault"}
             } = error.details

      for {kind, fun} <- [throw: fn _ -> throw(:fault) end, exit: fn _ -> exit(:fault) end] do
        assert {:error, error} = run_status(unquote(callback), fun)
        assert error.message == unquote(failure)

        assert error.details == %{
                 code: :plugin_callback_failed,
                 callback: unquote(callback),
                 plugin: CallbackPlugin,
                 kind: kind,
                 reason: :fault
               }
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

  defp run_command(:admit, command, fun), do: Plugin.admit(command, [spec(fun)], %{})

  defp run_status(:dispatch, fun) do
    Plugin.dispatch(spec(fun), nil, :directive, struct(DirectiveContext))
  end

  defp run_status(:await_ready, fun), do: Plugin.await_ready(spec(fun), nil)
end

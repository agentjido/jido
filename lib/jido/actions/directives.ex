defmodule Jido.Actions.Directives do
  @moduledoc """
  A collection of actions that are used to control the behavior of the agent.

  This module provides a set of simple, reusable actions:
  - EnqueueAction: Enqueues another action based on params
  - RegisterAction: Registers a new action module
  - DeregisterAction: Deregisters an existing action module

  Each action is implemented as a separate submodule and follows the Jido.DirectiveAction behavior.
  """

  defmodule EnqueueAction do
    @moduledoc false
    use Jido.Action,
      name: "enqueue_action",
      description: "Enqueues another action based on params",
      schema: [
        action: [type: :atom, required: true],
        params: [type: :map, default: %{}]
      ]

    @spec run(map(), map()) :: {:ok, map(), Jido.Agent.Directive.Enqueue.t()}
    def run(%{action: action} = input, context \\ %{}) do
      params = Map.get(input, :params, %{})
      opts = Map.get(input, :opts, [])

      directive = %Jido.Agent.Directive.Enqueue{
        action: action,
        params: params,
        context: context,
        opts: opts
      }

      {:ok, %{}, directive}
    end
  end

  defmodule RegisterAction do
    @moduledoc false
    use Jido.Action,
      name: "register_action",
      description: "Registers a new action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    @spec run(map(), map()) :: {:ok, map(), Jido.Agent.Directive.RegisterAction.t()}
    def run(%{action_module: action_module}, _context) do
      directive = %Jido.Agent.Directive.RegisterAction{
        action_module: action_module
      }

      {:ok, %{}, directive}
    end
  end

  defmodule DeregisterAction do
    @moduledoc false
    use Jido.Action,
      name: "deregister_action",
      description: "Deregisters an existing action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    @spec run(map(), map()) ::
            {:ok, map(), Jido.Agent.Directive.DeregisterAction.t()}
            | {:error, :cannot_deregister_self}
    def run(%{action_module: action_module}, _context) do
      # Prevent deregistering this module
      if action_module == __MODULE__ do
        {:error, :cannot_deregister_self}
      else
        directive = %Jido.Agent.Directive.DeregisterAction{
          action_module: action_module
        }

        {:ok, %{}, directive}
      end
    end
  end

  defmodule Spawn do
    @moduledoc false
    use Jido.Action,
      name: "spawn_process",
      description: "Spawns a child process under the agent's supervisor",
      schema: [
        module: [type: :atom, required: true, doc: "Module to spawn"],
        args: [type: :any, required: true, doc: "Arguments to pass to the module"]
      ]

    @spec run(map(), map()) :: {:ok, map(), Jido.Agent.Directive.Spawn.t()} | {:error, term()}
    def run(%{module: module, args: args}, _ctx) do
      directive = %Jido.Agent.Directive.Spawn{
        module: module,
        args: args
      }

      {:ok, %{}, directive}
    end
  end

  defmodule Kill do
    @moduledoc false
    use Jido.Action,
      name: "kill_process",
      description: "Terminates a child process",
      schema: [
        pid: [type: :pid, required: true, doc: "PID of process to terminate"]
      ]

    @spec run(map(), map()) :: {:ok, map(), Jido.Agent.Directive.Kill.t()} | {:error, term()}
    def run(%{pid: pid}, _ctx) do
      directive = %Jido.Agent.Directive.Kill{pid: pid}
      {:ok, %{}, directive}
    end
  end
end

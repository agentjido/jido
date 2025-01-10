defmodule Jido.Actions.Directives do
  @moduledoc """
  A collection of actions that are used to control the behavior of the agent.

  This module provides a set of simple, reusable actions:
  - EnqueueAction: Enqueues another action based on params
  - RegisterAction: Registers a new action module
  - DeregisterAction: Deregisters an existing action module

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule EnqueueAction do
    @moduledoc false
    use Action,
      name: "enqueue_action",
      description: "Enqueues another action based on params",
      schema: [
        action: [type: :atom, required: true],
        params: [type: :map, default: %{}]
      ]

    def run(%{action: action} = input, context \\ %{}) do
      params = Map.get(input, :params, %{})
      opts = Map.get(input, :opts, [])

      directive = %Jido.Agent.Directive.EnqueueDirective{
        action: action,
        params: params,
        context: context,
        opts: opts
      }

      {:ok, directive}
    end
  end

  defmodule RegisterAction do
    @moduledoc false
    use Action,
      name: "register_action",
      description: "Registers a new action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      directive = %Jido.Agent.Directive.RegisterActionDirective{
        action_module: action_module
      }

      {:ok, directive}
    end
  end

  defmodule DeregisterAction do
    @moduledoc false
    use Action,
      name: "deregister_action",
      description: "Deregisters an existing action module",
      schema: [
        action_module: [type: :atom, required: true]
      ]

    def run(%{action_module: action_module}, _context) do
      # Prevent deregistering this module
      if action_module == __MODULE__ do
        {:error, :cannot_deregister_self}
      else
        directive = %Jido.Agent.Directive.DeregisterActionDirective{
          action_module: action_module
        }

        {:ok, directive}
      end
    end
  end

  defmodule Spawn do
    @moduledoc false
    use Action,
      name: "spawn_process",
      description: "Spawns a child process under the agent's supervisor",
      schema: [
        module: [type: :atom, required: true, doc: "Module to spawn"],
        args: [type: :any, required: true, doc: "Arguments to pass to the module"]
      ]

    @spec run(map(), map()) :: {:ok, Jido.Agent.Directive.SpawnDirective.t()} | {:error, term()}
    def run(%{module: module, args: args}, _ctx) do
      directive = %Jido.Agent.Directive.SpawnDirective{
        module: module,
        args: args
      }

      {:ok, directive}
    end
  end

  defmodule Kill do
    @moduledoc false
    use Action,
      name: "kill_process",
      description: "Terminates a child process",
      schema: [
        pid: [type: :pid, required: true, doc: "PID of process to terminate"]
      ]

    @spec run(map(), map()) :: {:ok, Jido.Agent.Directive.KillDirective.t()} | {:error, term()}
    def run(%{pid: pid}, _ctx) do
      directive = %Jido.Agent.Directive.KillDirective{pid: pid}
      {:ok, directive}
    end
  end

  defmodule Publish do
    @moduledoc false
    use Action,
      name: "publish_message",
      description: "Publishes a message on a Jido Bus",
      schema: [
        stream_id: [type: :string, required: true, doc: "Stream ID to publish on"],
        signal: [type: :any, required: true, doc: "Signal to publish"]
      ]

    @spec run(map(), map()) :: {:ok, Jido.Agent.Directive.PublishDirective.t()} | {:error, term()}
    def run(%{stream_id: stream_id, signal: signal}, _ctx) do
      directive = %Jido.Agent.Directive.PublishDirective{
        stream_id: stream_id,
        signal: signal
      }

      {:ok, directive}
    end
  end

  defmodule Subscribe do
    @moduledoc false
    use Action,
      name: "subscribe_topic",
      description: "Subscribes to a PubSub topic",
      schema: [
        stream_id: [type: :string, required: true, doc: "Stream ID to subscribe to"]
      ]

    @spec run(map(), map()) ::
            {:ok, Jido.Agent.Directive.SubscribeDirective.t()} | {:error, term()}
    def run(%{stream_id: stream_id}, _ctx) do
      directive = %Jido.Agent.Directive.SubscribeDirective{stream_id: stream_id}
      {:ok, directive}
    end
  end

  defmodule Unsubscribe do
    @moduledoc false
    use Action,
      name: "unsubscribe_topic",
      description: "Unsubscribes from a PubSub topic",
      schema: [
        stream_id: [type: :string, required: true, doc: "Stream ID to unsubscribe from"]
      ]

    @spec run(map(), map()) ::
            {:ok, Jido.Agent.Directive.UnsubscribeDirective.t()} | {:error, term()}
    def run(%{stream_id: stream_id}, _ctx) do
      directive = %Jido.Agent.Directive.UnsubscribeDirective{stream_id: stream_id}
      {:ok, directive}
    end
  end
end

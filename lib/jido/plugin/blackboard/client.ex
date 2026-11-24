defmodule Jido.Plugin.Blackboard.Client do
  @moduledoc """
  Connects an Agent to a named board in its local Jido instance.

      plugins: [{Jido.Plugin.Blackboard.Client, %{name: "inventory", read_on: ["inventory.count"]}}]

  On matching Signals, the board snapshot is available as
  `context.plugin_inputs[Jido.Plugin.Blackboard.Client].runtime`. A failed
  board read rejects admission. Direct Agent commands can pass a snapshot in
  their own Signal data.

  Return a `Jido.Plugin.Blackboard.Client.Patch` Directive to request a write
  after commit. The client casts a `jido.blackboard.patch.result` Signal
  to the same activation. Its data includes the board name, request ID,
  status, and a revision when the patch succeeds. Status is one of
  `"ok"`, `"conflict"`, `"unavailable"`, `"timeout"`,
  `"indeterminate"`, or `"invalid_request"`. Keys are strings.

  Result delivery is best effort. A timeout, an indeterminate result, or a
  missing result can occur after the board applies the patch. Read the board
  before deciding how to proceed. The client does not retry the patch.
  """

  use Jido.Plugin, option_keys: [agent_server: [:name, :read_on, :timeout]]

  alias Jido.{AgentServer, Blackboard, Joi, Signal}
  alias Jido.Plugin.Blackboard.Client.Patch
  alias Jido.Plugin.{Context, Context.Admission, Init}
  alias Jido.Signal.{Router, Router.Route}

  @result_type "jido.blackboard.patch.result"
  @default_timeout 500
  @options Joi.object(%{
             name: Joi.string() |> Joi.min(1),
             read_on: Joi.list(Joi.string()) |> Joi.default([]),
             timeout: Joi.integer() |> Joi.min(1) |> Joi.max(4_294_967_295) |> Joi.default(@default_timeout)
           })

  @impl true
  def validate_options(opts) do
    with {:ok, parsed} <- Joi.parse(@options, Map.new(opts)) do
      if Enum.all?(parsed.read_on, &(Route.validate_path(&1, []) == :ok)),
        do: :ok,
        else: {:error, :invalid_read_path}
    end
  end

  @impl true
  def child_spec(%Init{agent_server: target, jido: instance, module: module}) do
    Supervisor.child_spec({Agent, fn -> {instance, target} end}, id: module)
  end

  @impl true
  def directives(_opts), do: [Patch]

  @impl true
  def admit(_runtime, %Admission{signal: %{type: @result_type}}, _opts), do: {:ok, nil}

  def admit(runtime, %Admission{signal: %{type: type}}, opts) do
    if Enum.any?(Keyword.get(opts, :read_on, []), &Router.matches?(type, &1)) do
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      with {:ok, {instance, _target}} <- binding(runtime, timeout) do
        Blackboard.read(instance, Keyword.fetch!(opts, :name), timeout)
      end
    else
      {:ok, nil}
    end
  end

  @impl true
  def dispatch(runtime, %Patch{} = patch, %Context{phase: :directive}, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    name = Keyword.fetch!(opts, :name)

    with {:ok, {instance, target}} <- binding(runtime, timeout) do
      result = Blackboard.patch(instance, name, patch.revision, patch.put, patch.delete, timeout)
      data = Map.merge(%{"board" => name, "request_id" => patch.request_id}, result_data(result))

      AgentServer.cast(target, Signal.new!(@result_type, data, source: "/jido/blackboard"))
    end
  end

  defp binding(runtime, timeout) do
    {:ok, Agent.get(runtime, & &1, timeout)}
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp result_data({:ok, snapshot}), do: %{"status" => "ok", "revision" => snapshot.revision}
  defp result_data({:error, reason}), do: %{"status" => Atom.to_string(reason)}
end

defmodule Jido.Topology.View do
  @moduledoc """
  Builds a safe, framework-neutral snapshot of one topology.

  The projector combines an accepted `Jido.Topology.Instance` with a status
  map from `Jido.Topology.Controller.status/2` or
  `Jido.Topology.Runtime.status/2`. It does not contact the Controller, Agent
  processes, or child runtimes.

  The result is a plain JSON document. It includes bounded Agent views and
  bounded summaries for resources, direct child topologies, and errors. It
  does not include PIDs, modules, nodes, Registry names, supervisors, input,
  initial state, metadata, resource configuration, or checkpoint data. Child
  summaries do not expand child definitions.
  """

  alias Jido.Agent.Authoring
  alias Jido.Agent.View, as: AgentView
  alias Jido.Codec.{Data, Registry}
  alias Jido.Topology.Instance

  @limits %{
    member_limit: {100, 500},
    operation_limit: {25, 500},
    resource_limit: {50, 100},
    child_limit: {50, 100},
    error_limit: {50, 100}
  }
  @status_values [:starting, :ready, :degraded]
  @member_status_values [:dormant, :starting, :ready, :error]
  @child_status_values [:dormant, :starting, :ready, :degraded, :failed]
  @activation_values [:eager, :deferred, :lazy]

  @type json_value :: nil | boolean() | number() | String.t() | [json_value()] | projection()
  @type projection :: %{required(String.t()) => json_value()}

  @doc """
  Projects one accepted topology instance and one status snapshot.

  The supported options are `:member_limit`, `:operation_limit`,
  `:resource_limit`, `:child_limit`, and `:error_limit`. A limit can be zero.
  Each result collection reports its total size and if it was truncated.
  """
  @spec project(Instance.t(), map(), Registry.t() | map(), keyword()) ::
          {:ok, projection()} | {:error, term()}
  def project(instance, status, registry, opts \\ [])

  def project(%Instance{} = instance, status, registry, opts)
      when is_map(status) and not is_struct(status) do
    with {:ok, opts} <- options(opts),
         {:ok, registry} <- Registry.new(registry),
         :ok <- Registry.require_stable(registry),
         {:ok, members} <- members(instance, status, registry, opts),
         resources <- resources(instance, opts.resource_limit),
         children <- children(instance, status, opts.child_limit),
         errors <- errors(instance, status, opts.error_limit),
         view <- build(instance, status, members, resources, children, errors),
         :ok <- Data.check_document(view) do
      {:ok, view}
    end
  end

  def project(_instance, _status, _registry, _opts),
    do: Authoring.error("Topology view requires an instance and a status map")

  defp options(opts) do
    with {:ok, opts} <- Authoring.attrs(opts),
         :ok <- Authoring.keys(opts, Map.keys(@limits)) do
      Enum.reduce_while(@limits, {:ok, %{}}, &put_limit(&1, &2, opts))
    end
  end

  defp put_limit({key, {default, maximum}}, {:ok, acc}, opts) do
    value = Map.get(opts, key, default)

    if is_integer(value) and value >= 0 and value <= maximum do
      {:cont, {:ok, Map.put(acc, key, value)}}
    else
      {:halt,
       Authoring.error("Topology view #{key} must be an integer from 0 through #{maximum}")}
    end
  end

  defp members(instance, status, registry, opts) do
    errors = Map.get(status, :errors, %{})
    entries = Enum.sort_by(instance.plan.agents, &elem(&1, 0))
    total = length(entries)

    with {:ok, items} <-
           entries
           |> Enum.take(opts.member_limit)
           |> Authoring.traverse(&member(&1, status, errors, registry, opts.operation_limit)) do
      {:ok, collection(items, total, opts.member_limit)}
    end
  end

  defp member({key, member}, status, errors, registry, operation_limit) do
    source = Map.get(member, :definition) || Map.get(member, :module)

    with {:ok, agent} <- AgentView.project(source, registry, operation_limit: operation_limit) do
      {:ok,
       %{
         "key" => key,
         "id" => member.id,
         "declaration" => member.declaration,
         "depends_on" => Enum.sort(member.depends_on),
         "status" => member_status(key, status, errors),
         "agent" => %{agent | "id" => member.id}
       }}
    end
  end

  defp resources(instance, limit) do
    entries = Enum.sort_by(instance.plan.resources, &elem(&1, 0))
    total = length(entries)

    items =
      entries
      |> Enum.take(limit)
      |> Enum.map(fn {key, resource} ->
        %{"key" => key, "kind" => safe_atom(resource.kind, [])}
      end)

    collection(items, total, limit)
  end

  defp children(instance, status, limit) do
    status_by_key = Map.get(status, :children, %{})
    entries = Enum.sort_by(instance.definition.children, & &1.key)
    total = length(entries)

    items =
      entries
      |> Enum.take(limit)
      |> Enum.map(fn child ->
        child_status = status_by_key |> map_value(child.key, %{}) |> plain_map()

        %{
          "key" => child.key,
          "name" => child.topology.name,
          "activation" => safe_atom(child.activation, @activation_values),
          "status" => safe_atom(Map.get(child_status, :status), @child_status_values, "unknown"),
          "error" => safe_error(Map.get(child_status, :error))
        }
      end)

    collection(items, total, limit)
  end

  defp errors(instance, status, limit) do
    known =
      instance.plan.agents
      |> Map.keys()
      |> Kernel.++(Map.keys(instance.plan.resources))
      |> MapSet.new()

    component_errors =
      status
      |> Map.get(:errors, %{})
      |> plain_map()
      |> Enum.map(fn {key, reason} ->
        component = if is_binary(key) and MapSet.member?(known, key), do: key, else: "topology"
        %{"component" => component, "code" => error_code(reason)}
      end)

    restore_errors =
      case Map.get(status, :restore_error) do
        nil -> []
        reason -> [%{"component" => "topology", "code" => error_code(reason)}]
      end

    child_errors =
      status
      |> Map.get(:children, %{})
      |> plain_map()
      |> Enum.flat_map(fn {key, child_status} ->
        case child_error(instance, key, child_status) do
          nil -> []
          error -> [error]
        end
      end)

    entries =
      Enum.sort_by(
        component_errors ++ restore_errors ++ child_errors,
        &{&1["component"], &1["code"]}
      )

    collection(Enum.take(entries, limit), length(entries), limit)
  end

  defp child_error(instance, key, child_status)
       when is_binary(key) and is_map(child_status) and not is_struct(child_status) do
    known? = Enum.any?(instance.definition.children, &(&1.key == key))

    if known? and not is_nil(Map.get(child_status, :error)) do
      %{"component" => "child/" <> key, "code" => error_code(child_status.error)}
    end
  end

  defp child_error(_instance, _key, _child_status), do: nil

  defp build(instance, status, members, resources, children, errors) do
    state = safe_atom(Map.get(status, :status), @status_values, "unknown")

    %{
      "type" => "jido.topology.view",
      "version" => 1,
      "id" => instance.id,
      "name" => instance.definition.name,
      "revision" => nonnegative(Map.get(status, :target_revision)),
      "activation" => safe_atom(Map.get(status, :activation), @activation_values, "unknown"),
      "readiness" => %{
        "status" => state,
        "ready" => ready?(status, state),
        "active_members" => nonnegative(Map.get(status, :active_members)),
        "dormant_members" => nonnegative(Map.get(status, :dormant_members)),
        "ready_components" => nonnegative(Map.get(status, :ready)),
        "pending_components" => nonnegative(Map.get(status, :pending))
      },
      "members" => members,
      "resources" => resources,
      "children" => children,
      "errors" => errors
    }
  end

  defp collection(items, total, limit) do
    %{"items" => items, "total" => total, "truncated" => total > limit}
  end

  defp member_status(key, status, errors) when is_map(errors) do
    statuses = Map.get(status, :member_statuses, %{})

    case map_value(statuses, key, nil) do
      value when value in @member_status_values -> Atom.to_string(value)
      _value -> if Map.has_key?(errors, key), do: "error", else: "unknown"
    end
  end

  defp member_status(_key, _status, _errors), do: "unknown"

  defp ready?(status, state) do
    case Map.get(status, :ready?) do
      value when is_boolean(value) -> value
      _value -> state == "ready"
    end
  end

  defp nonnegative(value) when is_integer(value) and value >= 0, do: value
  defp nonnegative(_value), do: 0

  defp map_value(map, key, default) when is_map(map) and not is_struct(map) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp map_value(_map, _key, default), do: default

  defp plain_map(value) when is_map(value) and not is_struct(value), do: value
  defp plain_map(_value), do: %{}

  defp safe_error(nil), do: nil
  defp safe_error(reason), do: %{"code" => error_code(reason)}

  defp error_code(reason) when is_atom(reason), do: safe_atom(reason, [])

  defp error_code(reason) when is_tuple(reason) and tuple_size(reason) > 0,
    do: reason |> elem(0) |> error_code()

  defp error_code(_reason), do: "topology_error"

  defp safe_atom(value, allowed, default \\ "unknown")
  defp safe_atom(value, [], default) when is_atom(value), do: safe_atom_name(value, default)

  defp safe_atom(value, allowed, default) when is_atom(value) do
    if value in allowed, do: Atom.to_string(value), else: default
  end

  defp safe_atom(_value, _allowed, default), do: default

  defp safe_atom_name(value, default) do
    name = Atom.to_string(value)

    if String.starts_with?(name, "Elixir.") or
         not Regex.match?(~r/^[a-z][a-z0-9_]*$/, name),
       do: default,
       else: name
  end
end

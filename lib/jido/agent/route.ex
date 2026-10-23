defmodule Jido.Agent.Route do
  @moduledoc "Pure route normalization and selection. Selection does not run a handler."
  alias Jido.Agent.{Data, Error}

  @helper_name ~r/\A[a-z][a-z0-9_]*\z/

  def normalize(value, related? \\ true) do
    with {:ok, route} <-
           Data.fields(value, [:path, :as, :defaults, :handler], %{
             as: nil,
             defaults: %{}
           }),
         :ok <- Error.at(Data.path(route[:path]), :path),
         :ok <- helper(route),
         :ok <- Error.at(Data.plain_map(route.defaults), :defaults),
         :ok <- Error.at(Data.static(route.defaults), :defaults),
         {:ok, handler} <- Error.at(handler(route[:handler], related?), :handler),
         :ok <- defaults(handler, route.defaults) do
      {:ok, Map.put(route, :handler, handler)}
    end
  end

  def executable(target) when is_atom(target) and target not in [nil, true, false] do
    with {:ok, executable} <- Jido.Instruction.resolve(target),
         :ok <- Jido.Instruction.validate(executable) do
      {:ok, %{kind: executable.kind, target: target}}
    else
      {:error, reason} ->
        Error.fail(:invalid_executable, [], "Expected an Action or Flow module", %{
          target: target,
          reason: reason
        })
    end
  end

  def executable(value),
    do: Error.fail(:invalid_executable, [], "Expected an executable module", %{target: value})

  # Internal Spark draft only. Public Map authoring never accepts this kind.
  defp handler(%{kind: :executable} = value, false) do
    with {:ok, value} <- Data.fields(value, [:kind, :target]),
         :ok <- Data.name(value[:target]),
         do: {:ok, value}
  end

  defp handler(%{kind: :forward} = value, _related?) do
    with {:ok, value} <- Data.fields(value, [:kind, :target]),
         {:ok, target} <- forward_target(value[:target]) do
      {:ok, %{value | target: target}}
    end
  end

  defp handler(%{kind: kind} = value, related?) when kind in [:action, :flow] do
    with {:ok, value} <- Data.fields(value, [:kind, :target]),
         :ok <- Data.name(value[:target]) do
      if related? do
        with {:ok, actual} <- executable(value.target) do
          if actual.kind == kind,
            do: {:ok, actual},
            else:
              Error.fail(:executable_kind, [], "Executable kind does not match the declared kind")
        end
      else
        {:ok, value}
      end
    end
  end

  defp handler(%{kind: :transform} = value, related?) do
    with {:ok, value} <- Data.fields(value, [:kind, :target]) do
      case value[:target] do
        {module, fun, 1}
        when is_atom(module) and is_atom(fun) and module not in [nil, true, false] ->
          if not related? or (Code.ensure_loaded?(module) and function_exported?(module, fun, 1)),
            do: {:ok, value},
            else:
              Error.fail(
                :unresolved_transform,
                [],
                "Transform must reference a public function of arity one",
                %{target: value.target}
              )

        _ ->
          Error.fail(:invalid_transform, [], "Transform requires {module, function, 1}")
      end
    end
  end

  defp handler(_, _),
    do:
      Error.fail(
        :invalid_handler,
        [],
        "Expected one Action, Flow, transform, or forward handler"
      )

  defp helper(%{as: nil}), do: :ok

  defp helper(route) do
    with :ok <- Error.at(Data.name(route.as), :as),
         :ok <- Error.at(helper_name(route.as), :as) do
      if Data.wildcard?(route.path),
        do: Error.fail(:wildcard_helper, :as, "A helper requires an exact input type"),
        else: :ok
    end
  end

  defp helper_name(value) do
    if Regex.match?(@helper_name, Atom.to_string(value)),
      do: :ok,
      else:
        Error.fail(
          :invalid_helper_name,
          [],
          "A helper name must start with a lowercase letter and contain only lowercase letters, digits, and underscores"
        )
  end

  defp defaults(%{kind: kind}, defaults)
       when kind in [:transform, :forward] and map_size(defaults) > 0,
       do: Error.fail(:invalid_defaults, :defaults, "Only Action and Flow routes accept defaults")

  defp defaults(_, _), do: :ok

  defp forward_target(%{kind: :agent} = target) do
    with {:ok, target} <- Data.fields(target, [:kind, :name]),
         :ok <- Data.name(target[:name]) do
      if target.name == :root,
        do: Error.fail(:self_forward, [], "Forward cannot target the current Agent"),
        else: {:ok, target}
    end
  end

  defp forward_target(%{kind: :parent} = target), do: Data.fields(target, [:kind])

  defp forward_target(_target),
    do: Error.fail(:invalid_forward_target, [], "Forward requires agent(name) or parent()")

  def select(%{routes: routes}, type), do: select(routes, type)

  def select(routes, type) when is_list(routes) do
    with :ok <- Data.exact(type) do
      case Enum.find(routes, &Data.matches?(type, &1.path)) do
        nil ->
          Error.fail(:unmatched_input, [:routes], "No route accepts this Signal type", %{
            type: type
          })

        route ->
          {:ok, route}
      end
    end
  end

  def params(%{handler: %{kind: kind}, defaults: defaults}, data) when kind in [:action, :flow] do
    with :ok <- Data.plain_map(data), do: {:ok, Map.merge(defaults, data)}
  end

  def params(_, _),
    do: Error.fail(:invalid_handler, [:handler], "Only Action and Flow routes have parameters")
end

defmodule Jido.Agent.Route do
  @moduledoc "Pure route normalization and selection. Selection does not run a handler."
  alias Jido.Agent.{Data, Error}

  @helper_name ~r/\A[a-z][a-z0-9_]*\z/
  @route_fields [:path, :as, :defaults, :handler, :state, :reply]

  def normalize(value, related? \\ true) do
    with {:ok, route} <- Data.fields(value, @route_fields, %{as: nil, defaults: %{}, reply: nil}),
         :ok <- Error.at(Data.path(route[:path]), :path),
         :ok <- helper(route),
         :ok <- Error.at(Data.plain_map(route.defaults), :defaults),
         :ok <- Error.at(Data.static(route.defaults), :defaults),
         {:ok, handler} <- Error.at(handler(route[:handler], related?), :handler),
         :ok <- defaults(handler, route.defaults) do
      route
      |> Map.put(:handler, handler)
      |> Map.put_new(:state, default_state(handler))
      |> mappings(related?)
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

  # :executable is an internal Spark draft. Public Map authoring rejects it.
  defp handler(%{kind: kind} = value, related?)
       when kind in [:action, :flow, :forward, :transform] or
              (kind == :executable and related? == false) do
    with {:ok, value} <- Data.fields(value, [:kind, :target]),
         {:ok, target} <- handler_target(kind, value[:target], related?) do
      {:ok, %{kind: kind, target: target}}
    end
  end

  defp handler(_, _),
    do:
      Error.fail(:invalid_handler, [], "Expected one Action, Flow, transform, or forward handler")

  defp handler_target(:forward, target, _related?), do: forward_target(target)

  defp handler_target(kind, target, related?) when kind in [:action, :flow, :executable] do
    with :ok <- Data.name(target) do
      if related? do
        with {:ok, actual} <- executable(target) do
          if actual.kind == kind,
            do: {:ok, target},
            else:
              Error.fail(:executable_kind, [], "Executable kind does not match the declared kind")
        end
      else
        {:ok, target}
      end
    end
  end

  defp handler_target(:transform, {module, fun, 1} = target, related?)
       when is_atom(module) and is_atom(fun) and module not in [nil, true, false] do
    if not related? or (Code.ensure_loaded?(module) and function_exported?(module, fun, 1)),
      do: {:ok, target},
      else:
        Error.fail(
          :unresolved_transform,
          [],
          "Transform must reference a public function of arity one",
          %{
            target: target
          }
        )
  end

  defp handler_target(:transform, _target, _related?),
    do: Error.fail(:invalid_transform, [], "Transform requires {module, function, 1}")

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

  defp mappings(%{handler: %{kind: kind}} = route, related?)
       when kind in [:action, :flow, :executable] do
    with {:ok, state} <- Error.at(state(route.state), :state),
         {:ok, reply} <- Error.at(reply(route.reply), :reply) do
      resolve_mappings(%{route | state: state, reply: reply}, related?)
    end
  end

  defp mappings(%{handler: %{kind: kind}, state: state}, _related?)
       when kind in [:forward, :transform] and state != :unchanged,
       do: Error.fail(:terminal_state, [:state], "A terminal route cannot select output state")

  defp mappings(%{handler: %{kind: kind}, reply: reply}, _related?)
       when kind in [:forward, :transform] and not is_nil(reply),
       do: Error.fail(:terminal_reply, [:reply], "A terminal route cannot declare a reply")

  defp mappings(%{handler: %{kind: kind}} = route, _related?)
       when kind in [:forward, :transform],
       do: {:ok, Map.put(route, :state, :unchanged)}

  defp default_state(%{kind: kind}) when kind in [:action, :flow, :executable],
    do: %{source: :output, path: []}

  defp default_state(%{kind: kind}) when kind in [:forward, :transform], do: :unchanged

  defp state(:unchanged), do: {:ok, :unchanged}
  defp state(value), do: selector(value)

  defp reply(nil), do: {:ok, nil}

  defp reply(value) do
    with {:ok, reply} <- required_fields(value, [:type, :from], "Reply requires type and from"),
         :ok <- Error.at(Data.exact(reply.type), :type),
         {:ok, from} <- Error.at(selector(reply.from), :from) do
      {:ok, %{reply | from: from}}
    end
  end

  defp selector(value) do
    with {:ok, selector} <-
           required_fields(value, [:source, :path], "Output selector requires source and path"),
         :ok <- output_source(selector.source),
         {:ok, path} <- Error.at(selector_path(selector.path), :path) do
      {:ok, %{source: :output, path: path}}
    end
  end

  defp output_source(:output), do: :ok

  defp output_source(_value),
    do: Error.fail(:invalid_selector_source, [:source], "Selector source must be output")

  defp selector_path(path) do
    Data.list(path, fn
      key when is_atom(key) or is_binary(key) -> {:ok, key}
      _key -> Error.fail(:invalid_selector_key, [], "Output path keys must be atoms or strings")
    end)
  end

  defp required_fields(value, fields, message) do
    with :ok <- Data.plain_map(value) do
      missing = Enum.reject(fields, &Map.has_key?(value, &1))

      if missing == [],
        do: Data.fields(value, fields),
        else: Error.fail(:missing_fields, [], message, %{keys: missing})
    end
  end

  defp resolve_mappings(route, false), do: {:ok, route}

  defp resolve_mappings(%{state: :unchanged, reply: nil} = route, true), do: {:ok, route}

  defp resolve_mappings(route, true) do
    first_path = if route.state == :unchanged, do: [:reply, :from], else: [:state]

    with {:ok, schema} <- Error.at(output_schema(route.handler), first_path),
         {:ok, state} <- Error.at(resolve_selector(route.state, schema), :state),
         {:ok, reply} <- Error.at(resolve_selector(route.reply, schema), :reply) do
      {:ok, %{route | state: state, reply: reply}}
    end
  end

  defp output_schema(%{target: target}) do
    if function_exported?(target, :output_schema, 0),
      do: output_schema_value(target.output_schema()),
      else: Error.fail(:missing_output_schema, [], "Executable has no output schema")
  rescue
    reason ->
      Error.fail(:invalid_output_schema, [], "Executable output schema failed", %{reason: reason})
  end

  defp output_schema_value(schema) do
    if is_struct(schema) and Zoi.Type.impl_for(schema) != nil,
      do: {:ok, schema},
      else: Error.fail(:invalid_output_schema, [], "Executable output schema is invalid")
  end

  defp resolve_selector(value, _schema) when value in [:unchanged, nil], do: {:ok, value}

  defp resolve_selector(%{from: from} = reply, schema) do
    with {:ok, from} <- Error.at(resolve_selector(from, schema), :from),
         do: {:ok, %{reply | from: from}}
  end

  defp resolve_selector(selector, schema) do
    with {:ok, path} <- resolve_path(schema, selector.path, 0),
         do: {:ok, %{selector | path: path}}
  end

  defp resolve_path(_schema, [], _index), do: {:ok, []}

  defp resolve_path(schema, [key | rest], index) do
    with {:ok, declared_key, child_schema} <- output_field(schema, key, index),
         {:ok, rest} <- resolve_path(child_schema, rest, index + 1) do
      {:ok, [declared_key | rest]}
    end
  end

  defp output_field(%{__struct__: type, fields: fields}, key, index)
       when type in [Zoi.Types.Map, Zoi.Types.Struct] and is_list(fields) do
    matches =
      for {declared_key, schema} <- fields,
          is_atom(declared_key) or is_binary(declared_key),
          to_string(declared_key) == to_string(key),
          do: {declared_key, schema}

    case matches do
      [{declared_key, schema}] ->
        {:ok, declared_key, schema}

      [] ->
        Error.fail(:unknown_output_field, [:path, index], "Output path field is not declared", %{
          key: key
        })

      _many ->
        Error.fail(
          :ambiguous_output_field,
          [:path, index],
          "Output path field name is ambiguous",
          %{key: key}
        )
    end
  end

  defp output_field(_schema, key, index),
    do:
      Error.fail(
        :unsupported_output_path,
        [:path, index],
        "Output paths can traverse only object or struct fields",
        %{key: key}
      )

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

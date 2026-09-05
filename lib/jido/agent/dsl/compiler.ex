defmodule Jido.Agent.DSL.Compiler do
  @moduledoc false

  alias Jido.Agent.Authoring
  alias Spark.Dsl.Extension

  defmacro __before_compile__(env) do
    original = Module.get_attribute(env.module, :jido_agent_options)
    config = unwrap!(Authoring.attrs(original), env)
    # Module access can read an older loaded version during recompilation.
    dsl = Module.get_attribute(env.module, :spark_dsl_config) || %{}
    routes = Extension.get_entities(dsl, [:routes])
    plugins = Extension.get_entities(dsl, [:agent])
    fields = block_fields(dsl, routes, plugins, env)
    overlap = Map.keys(fields) |> Enum.filter(&Map.has_key?(config, &1))

    if overlap != [],
      do: fail!(env, "Fields declared in both keyword and block form: #{inspect(overlap)}")

    config =
      Map.merge(
        %{description: nil, schema: Zoi.object(%{}), metadata: %{}, routes: [], plugins: []},
        Map.merge(config, fields)
      )

    source = Extension.get_opt(dsl, [:routes], :signal_source)
    interfaces = interfaces(routes, source, env)

    generated = generate(interfaces, env)
    block? = fields != %{} or source != nil

    quote do
      @doc false
      def __agent_config__, do: unquote(Macro.escape(config))

      @doc false
      def __agent_interfaces__, do: unquote(Macro.escape(interfaces))

      unquote_splicing(generated)

      if unquote(block?) do
        @after_verify {Jido.Agent.DSL.Compiler, :verify}
      end
    end
  end

  def verify(module) do
    interfaces = module.__agent_interfaces__()
    env = %{file: to_string(module.module_info(:compile)[:source]), line: 1}
    unwrap!(Jido.Agent.__definition_from_module__(module, module.__agent_config__()), env)
    Enum.each(interfaces, &verify_fields!(&1, env))
    :ok
  end

  defp block_fields(dsl, routes, plugins, env) do
    fields =
      Enum.reduce([:schema, :metadata], %{}, fn key, acc ->
        case Extension.fetch_opt(dsl, [:agent], key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
      end)

    fields =
      if routes == [],
        do: fields,
        else: Map.put(fields, :routes, Enum.map(routes, &lower_route(&1, env)))

    if plugins == [] do
      fields
    else
      declarations =
        Enum.map(plugins, fn plugin ->
          options = unwrap!(Authoring.options(plugin.config), env)
          {plugin.module, options}
        end)

      Map.put(fields, :plugins, declarations)
    end
  end

  defp lower_route(route, env) do
    opts = [priority: route.priority, match: route.match]
    opts = if is_nil(route.defaults), do: opts, else: Keyword.put(opts, :defaults, route.defaults)
    unwrap!(Authoring.route(route.path, route.target, opts), location(env, route))
  end

  defp interfaces(routes, source, env) do
    Enum.flat_map(routes, fn route ->
      Enum.map(route.interfaces, fn interface ->
        env = location(env, interface)

        if String.contains?(route.path, "*") or route.match != nil,
          do: fail!(env, "define requires an exact route without a match predicate")

        if Enum.count(routes, &(&1.path == route.path)) > 1,
          do: fail!(env, "An exposed Signal type must have exactly one route")

        if not is_binary(source), do: fail!(env, "signal_source is required for define")

        case Jido.Signal.validate_uri_reference(source, []) do
          :ok -> :ok
          {:error, reason} -> fail!(env, "Invalid signal_source: #{reason}")
        end

        {fields, required} = arguments!(interface.args, env)

        target =
          case route.target do
            {target, defaults} when is_map(defaults) -> target
            target -> target
          end

        %{
          name: interface.name,
          fields: fields,
          required: required,
          path: route.path,
          target: target,
          source: source,
          line: env.line
        }
      end)
    end)
  end

  defp arguments!(args, env) when is_list(args) do
    {fields, required, _optional?} =
      Enum.reduce(args, {[], 0, false}, fn
        {:optional, field}, {fields, required, _} when is_atom(field) ->
          {[field | fields], required, true}

        field, {fields, required, false} when is_atom(field) ->
          {[field | fields], required + 1, false}

        _, _ ->
          fail!(env, "args must contain unique field names with optional arguments last")
      end)

    if length(fields) != length(Enum.uniq(fields)), do: fail!(env, "Duplicate interface argument")
    {Enum.reverse(fields), required}
  end

  defp arguments!(_args, env), do: fail!(env, "args must be a list")

  defp generate(interfaces, env) do
    names = Enum.map(interfaces, & &1.name)
    if length(names) != length(Enum.uniq(names)), do: fail!(env, "Duplicate interface name")

    {_seen, code} =
      Enum.reduce(interfaces, {MapSet.new(), []}, fn interface, acc ->
        Enum.reduce([:call, :signal, :signal!], acc, fn mode, {seen, code} ->
          name = function_name(interface.name, mode)
          offset = if mode == :call, do: 1, else: 0

          Enum.reduce(
            (interface.required + offset)..(length(interface.fields) + offset + 1),
            {seen, code},
            fn arity, {seen, code} ->
              key = {name, arity}

              if MapSet.member?(seen, key) or Module.defines?(env.module, key),
                do:
                  fail!(
                    %{env | line: interface.line},
                    "Generated function conflicts with #{name}/#{arity}"
                  )

              {MapSet.put(seen, key),
               [Jido.Agent.DSL.Generator.function(interface, name, mode, arity) | code]}
            end
          )
        end)
      end)

    Enum.reverse(code)
  end

  defp function_name(name, :call), do: name
  defp function_name(name, :signal), do: String.to_atom("#{name}_signal")
  defp function_name(name, :signal!), do: String.to_atom("#{name}_signal!")

  defp verify_fields!(interface, env) do
    env = %{env | line: interface.line}

    schema =
      case interface.target do
        %Jido.Flow{schema: schema} ->
          schema

        module when is_atom(module) ->
          if function_exported?(module, :schema, 0),
            do: module.schema(),
            else: fail!(env, "Interface target must expose its executable input schema")

        _ ->
          fail!(env, "Interface target must be an Action or Flow")
      end

    fields =
      case schema do
        %Zoi.Types.Map{fields: fields} ->
          fields

        [] ->
          []

        _ ->
          if interface.fields == [],
            do: [],
            else: fail!(env, "Positional args require a field-based Zoi input schema")
      end

    Enum.each(interface.fields, fn key ->
      if not Keyword.has_key?(fields, key),
        do: fail!(env, "Unknown executable input field #{inspect(key)}")
    end)

    interface.fields
    |> Enum.drop(interface.required)
    |> Enum.each(fn key ->
      if list_input?(Keyword.fetch!(fields, key)),
        do: fail!(env, "Optional keyword/list input #{inspect(key)} must use input options")
    end)
  end

  defp list_input?(%Zoi.Types.Literal{value: value}), do: is_list(value)

  defp list_input?(%{__struct__: module} = schema) do
    module in [Zoi.Types.Any, Zoi.Types.Array, Zoi.Types.Keyword] or
      Enum.any?(Map.take(schema, [:inner, :schema, :schemas, :from]), fn
        {_, values} when is_list(values) -> Enum.any?(values, &list_input?/1)
        {_, inner} -> list_input?(inner)
      end)
  end

  defp list_input?(_schema), do: false

  defp location(env, %{__spark_metadata__: %{anno: anno}}) when not is_nil(anno),
    do: %{env | line: :erl_anno.line(anno)}

  defp location(env, _entity), do: env

  defp unwrap!({:ok, value}, _env), do: value
  defp unwrap!({:error, error}, env), do: fail!(env, Exception.message(error))

  defp fail!(env, message),
    do: raise(CompileError, file: env.file, line: env.line, description: message)
end

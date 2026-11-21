defmodule Jido.Agent.DSL.State do
  @moduledoc false

  @options Jido.Agent.DSL.Extension.State.Options

  defmacro schema(value) do
    claim!(__CALLER__)

    quote do
      require unquote(@options)
      unquote(@options).__state_schema__(unquote(value))
    end
  end

  defmacro state_source(provider, options) do
    claim!(__CALLER__)

    quote do
      @jido_state_provider Jido.Agent.DSL.State.compile!(unquote(provider), unquote(options), __ENV__)
      require unquote(@options)
      unquote(@options).__state_schema__(elem(@jido_state_provider, 2))
    end
  end

  @doc false
  def compile!(provider, options, env) do
    with {:module, ^provider} <- Code.ensure_compiled(provider),
         true <-
           Enum.all?([state_source: 2, open: 5, refresh: 3, apply_state: 5], fn {name, arity} ->
             function_exported?(provider, name, arity)
           end) do
      {schema, descriptor} = provider.state_source(options, env)

      unless Jido.Joi.Schema.kind(schema) == :map and
               match?({:ok, fields} when is_list(fields), Jido.Joi.Schema.fields(schema)) do
        raise CompileError,
          file: env.file,
          line: env.line,
          description: "An Agent state source must declare its fields with a Joi object schema"
      end

      {provider, descriptor, schema}
    else
      _ -> raise CompileError, file: env.file, line: env.line, description: "Invalid Agent state source Plugin"
    end
  end

  @doc false
  def validate_plugin!(nil, _definition, _env), do: :ok

  def validate_plugin!({provider, _descriptor, _schema}, definition, env) do
    unless Enum.any?(definition.plugins, &(&1.provider == provider)) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Add #{inspect(provider)} to the Agent's :plugins to use it as a state source"
    end
  end

  @doc false
  def declaration(module) when is_atom(module) and module not in [nil, true, false] do
    if Code.ensure_loaded?(module) and function_exported?(module, :__jido_state_provider__, 0),
      do: module.__jido_state_provider__()
  end

  def declaration(_module), do: nil

  defp claim!(env) do
    if Module.has_attribute?(env.module, :jido_state_schema_origin) do
      raise CompileError,
        file: env.file,
        line: env.line,
        description: "Agent state accepts exactly one schema source (schema or state_source)"
    end

    Module.put_attribute(env.module, :jido_state_schema_origin, env.line)
  end
end

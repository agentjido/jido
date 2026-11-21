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

  defmacro state_provider(provider, options) do
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
           Enum.all?([compile_state!: 2, open: 5, refresh: 3, commit: 5], fn {name, arity} ->
             function_exported?(provider, name, arity)
           end) do
      {schema, descriptor} = provider.compile_state!(options, env)
      {provider, descriptor, schema}
    else
      _ -> raise CompileError, file: env.file, line: env.line, description: "Invalid Agent state provider"
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
        description: "Agent state accepts exactly one schema source (schema or state_provider)"
    end

    Module.put_attribute(env.module, :jido_state_schema_origin, env.line)
  end
end

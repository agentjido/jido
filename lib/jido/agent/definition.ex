defmodule Jido.Agent.Definition do
  @moduledoc false

  defmacro __using__(opts) do
    host = Keyword.fetch!(opts, :host)
    agent_opts = Keyword.fetch!(opts, :agent_options)

    dsl =
      case host do
        :agent -> Jido.Agent.DSL
        :topology -> Jido.Topology.DSL
      end

    quote location: :keep do
      @jido_agent_options Jido.Agent.Definition.options!(unquote(agent_opts), __ENV__)
      Jido.Agent.Definition.setup_dsl(__ENV__, unquote(dsl), @jido_agent_options)
      import Jido.Agent.Definition, only: [agent: 1, routes: 1, topology: 1]
      unquote_splicing(extension_imports(agent_opts, __CALLER__))
      use Jido.Action.Inline
      @before_compile Jido.Agent.DSL.Compiler
      @behaviour Jido.Agent

      @jido_agent_host unquote(host)

      @doc "Returns the neutral canonical Agent definition."
      @spec definition() :: Jido.Agent.definition()
      def definition do
        case Jido.Agent.Source.definition(__MODULE__) do
          {:ok, definition} -> definition
          {:error, error} -> raise error
        end
      end

      @doc "Returns the positive Agent definition version owned by this module."
      @spec vsn() :: pos_integer()
      def vsn, do: __agent_config__().vsn

      @doc "Returns the authored Agent data schema."
      @spec domain_schema() :: Zoi.schema()
      def domain_schema, do: __agent_config__().schema

      @doc "Returns the complete data schema, including Plugin-owned fields in Agent state."
      @spec complete_schema() :: Zoi.schema()
      def complete_schema do
        case Jido.Agent.Source.definition_with_plugins(__MODULE__) do
          {:ok, _definition, _specs, schema} -> schema
          {:error, error} -> raise error
        end
      end

      @doc "Returns the Action target compiled for one inline route."
      @spec route_action!(String.t()) :: module()
      def route_action!(path) do
        Jido.Action.Inline.target!(__MODULE__, host: Jido.Agent, route: path, role: :action)
      end

      @doc "Applies one Signal to an Agent value without starting a Server."
      @spec cmd(Jido.Agent.instance(), Jido.Signal.t(), keyword()) ::
              {:ok, Jido.Agent.instance(), [struct()]} | {:error, term()}
      def cmd(agent, signal, opts \\ []), do: Jido.Agent.cmd(agent, signal, opts)
    end
  end

  def options!(value, env) do
    case Jido.Agent.Authoring.attrs(value) do
      {:ok, options} ->
        options

      {:error, error} ->
        raise CompileError, file: env.file, line: env.line, description: Exception.message(error)
    end
  end

  # Evaluate options in the module body, after its attributes exist. Spark needs
  # literal options when it expands, so install it in this evaluated scope.
  def setup_dsl(env, dsl, options) do
    extensions = Map.get(options, :extensions, [])

    {_, _, configured_env} =
      Code.eval_quoted_with_env(
        quote(do: use(unquote(dsl), extensions: unquote(Macro.escape(extensions)))),
        [],
        env
      )

    imports =
      for key <- [:functions, :macros, :requires], into: %{} do
        {key, Map.fetch!(configured_env, key) -- Map.fetch!(env, key)}
      end

    Module.put_attribute(env.module, :jido_dsl_imports, imports)

    :ok
  end

  def eval_block(env, name, body, bindings) do
    imports = Module.get_attribute(env.module, :jido_dsl_imports)

    env = %{
      env
      | functions: Keyword.merge(env.functions, imports.functions),
        macros: env.macros |> Keyword.merge(imports.macros) |> Keyword.delete(__MODULE__),
        requires: Enum.uniq(env.requires ++ imports.requires)
    }

    Code.eval_quoted(
      {name, [line: env.line], [[do: body]]},
      bindings,
      env
    )

    :ok
  end

  # Keep extension-owned root sections available for literal extension options.
  defp extension_imports(options, env) do
    extensions =
      case options do
        {:%{}, _, entries} -> Keyword.get(entries, :extensions, [])
        entries when is_list(entries) -> Keyword.get(entries, :extensions, [])
        _ -> []
      end

    if is_list(extensions) do
      extensions =
        extensions
        |> Enum.map(fn
          {:__aliases__, _, _} = alias -> Macro.expand(alias, env)
          value -> value
        end)
        |> Enum.filter(&(is_atom(&1) and not is_nil(&1)))

      # Spark root macros read this attribute during expansion. The evaluated
      # setup later installs the complete extension set, including defaults.
      Module.put_attribute(env.module, :extensions, extensions)

      extensions
      |> Spark.Dsl.Extension.prepare()
      |> Enum.flat_map(fn
        {:__block__, _, forms} -> forms
        form -> [form]
      end)
      |> Enum.filter(fn
        {:import, _, _} -> true
        {:require, _, _} -> true
        _ -> false
      end)
    else
      []
    end
  end

  # Expand blocks after the module body has evaluated the options. Spark owns
  # the block contents and supplies the imports captured during setup.
  for name <- [:agent, :routes, :topology] do
    defmacro unquote(name)(do: body) do
      name = unquote(name)

      quote do
        Jido.Agent.Definition.eval_block(
          __ENV__,
          unquote(name),
          unquote(Macro.escape(body)),
          binding()
        )
      end
    end
  end
end

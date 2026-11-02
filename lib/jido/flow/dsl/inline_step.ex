defmodule Jido.Flow.DSL.InlineStep do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Authoring.Options
  alias Jido.Flow.DSL.{MacroSupport, ValueParser}

  @action_fields [:name, :description, :schema, :output_schema, :context]
  @step_fields [:needs, :meta, :policy, :timeout_ms, :retry, :on_error]
  @pending_action :__jido_flow_pending_inline_step__

  @doc false
  @spec parse!(Macro.t(), keyword(), Macro.Env.t()) :: map() | no_return()
  def parse!(bindings, options, caller) do
    validate_options!(options, caller)

    case Keyword.get(options, :do) do
      [{:->, metadata, _clauses} | _rest] ->
        MacroSupport.compile_error!(
          %{caller | line: Keyword.get(metadata, :line, caller.line)},
          "use case inside the inline Step body; top-level clause bodies are not supported"
        )

      _other ->
        :ok
    end

    action_options = inline_options!(options, caller) ++ Keyword.take(options, [:do])

    parsed =
      try do
        Inline.parse_bound!(bindings, action_options, caller)
      rescue
        error in CompileError ->
          reraise %{
                    error
                    | description:
                        String.replace(error.description, "inline Action", "inline Step")
                  },
                  __STACKTRACE__
      end

    validate_sources!(bindings, caller)

    %{
      action: parsed,
      component_options: Keyword.drop(options, [:do, :inline])
    }
  end

  @doc false
  @spec parse!(Macro.t(), keyword(), keyword(), Macro.Env.t()) :: map() | no_return()
  def parse!(bindings, options, body_options, caller),
    do: parse!(bindings, merge_options!(options, body_options, caller), caller)

  @doc false
  @spec defer!(list()) :: :ok
  def defer!(args) do
    caller = List.last(args)
    Module.put_attribute(caller.module, @pending_action, args)
  end

  @doc false
  @spec emit!(Macro.Env.t()) :: term()
  def emit!(caller) do
    args = Module.delete_attribute(caller.module, @pending_action)
    apply(Inline.Compiler, :create_action!, args)
  end

  @doc false
  @spec declaration_imports(Macro.Env.t()) :: [{module(), [{atom(), arity()}]}]
  def declaration_imports(caller) do
    modules =
      caller.functions
      |> Keyword.keys()
      |> Kernel.++(Keyword.keys(caller.macros))
      |> Enum.uniq()
      |> Enum.filter(&flow_declaration_module?/1)

    for module <- modules,
        imports =
          Keyword.get(caller.functions, module, []) ++ Keyword.get(caller.macros, module, []),
        imports != [],
        do: {module, Enum.uniq(imports)}
  end

  defp flow_declaration_module?(Spark.Dsl), do: true

  defp flow_declaration_module?(module) do
    String.starts_with?(Atom.to_string(module), "Elixir.Jido.Flow.")
  end

  defp merge_options!(options, body_options, caller) do
    validate_options!(options, caller)
    validate_options!(body_options, caller)
    options ++ body_options
  end

  defp validate_options!(options, caller) do
    MacroSupport.validate_options!(
      options,
      caller,
      "inline Step options must be a keyword list",
      "inline Step field"
    )

    Options.allowed!(
      options,
      @step_fields ++ [:inline, :do],
      caller,
      "inline Step field",
      "; use only needs:, meta:, inline:, and do:"
    )
  end

  defp inline_options!(options, caller) do
    case Keyword.fetch(options, :inline) do
      :error ->
        []

      {:ok, inline_options} ->
        MacroSupport.validate_options!(
          inline_options,
          caller,
          "inline Step settings must be a keyword list",
          "inline Step setting"
        )

        Options.allowed!(inline_options, @action_fields, caller, "inline Step setting")
        inline_options
    end
  end

  defp validate_sources!(bindings, caller) do
    for {:<-, _, [_pattern, source]} <- List.wrap(bindings) do
      validate_source!(source, caller)
    end

    :ok
  end

  defp validate_source!(source, caller) do
    with {:ok, expression} <- ValueParser.parse(source),
         :ok <- reject_source_operations(expression) do
      :ok
    else
      {:error, error} ->
        line =
          case source do
            {_form, metadata, _arguments} -> Keyword.get(metadata, :line, caller.line)
            _other -> caller.line
          end

        MacroSupport.compile_error!(
          %{caller | line: line},
          "inline Step binding source: #{error.message}"
        )
    end
  end

  defp reject_source_operations(%Jido.Expr{}) do
    {:error,
     Jido.Flow.Error.validation_error(
       "Flow operations are not allowed; move the calculation into the inline body"
     )}
  end

  defp reject_source_operations(map) when is_map(map) and not is_struct(map) do
    Enum.reduce_while(map, :ok, fn {_key, value}, :ok ->
      case reject_source_operations(value) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp reject_source_operations(list) when is_list(list) do
    Enum.reduce_while(list, :ok, fn value, :ok ->
      case reject_source_operations(value) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end

  defp reject_source_operations(_value), do: :ok
end

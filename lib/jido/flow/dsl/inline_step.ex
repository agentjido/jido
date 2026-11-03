defmodule Jido.Flow.DSL.InlineStep do
  @moduledoc false

  alias Jido.Action.Inline
  alias Jido.Codec.Config
  alias Jido.Flow.DSL.{ValueParser, MacroSupport}

  @action_fields [:name, :description, :schema, :output_schema, :context]
  @component_fields [:needs, :meta]
  @pending_action :__jido_flow_pending_inline_action__

  @type parsed :: %{action: Inline.t(), component_options: keyword()}

  @doc false
  @spec parse!(Macro.t(), term(), Macro.Env.t()) :: parsed()
  def parse!(bindings, options, caller) do
    parse!(bindings, options, caller, "inline Step", @component_fields)
  end

  @doc false
  @spec parse_parallel_action!(Macro.t(), term(), Macro.Env.t()) :: parsed()
  def parse_parallel_action!(bindings, options, caller) do
    parse!(bindings, options, caller, "inline Parallel action", [])
  end

  defp parse!(bindings, options, caller, label, component_fields) do
    validate_options!(options, caller, label, component_fields)

    case Keyword.get(options, :do) do
      [{:->, metadata, _} | _] ->
        MacroSupport.compile_error!(
          %{caller | line: Keyword.get(metadata, :line, caller.line)},
          "use case inside the #{label} body; top-level clause bodies are not supported"
        )

      _ ->
        :ok
    end

    action_options = inline_options!(options, caller, label) ++ Keyword.take(options, [:do])

    parsed =
      try do
        Inline.parse_bound!(bindings, action_options, caller)
      rescue
        error in CompileError ->
          reraise %{
                    error
                    | description: String.replace(error.description, "inline Action", label)
                  },
                  __STACKTRACE__
      end

    validate_sources!(bindings, caller, label)

    %{
      action: parsed,
      component_options: Keyword.drop(options, [:do, :inline])
    }
  end

  @doc false
  @spec parse!(Macro.t(), Macro.t(), term(), Macro.Env.t()) :: parsed()
  def parse!(bindings, options, body_options, caller),
    do:
      parse!(
        bindings,
        merge_options!(options, body_options, caller, "inline Step"),
        caller
      )

  @doc false
  @spec parse_parallel_action!(Macro.t(), Macro.t(), term(), Macro.Env.t()) :: parsed()
  def parse_parallel_action!(bindings, options, body_options, caller),
    do:
      parse_parallel_action!(
        bindings,
        merge_options!(options, body_options, caller, "inline Parallel action"),
        caller
      )

  @doc false
  @spec defer!([term()]) :: :ok
  def defer!(args) do
    caller = List.last(args)
    Module.put_attribute(caller.module, @pending_action, args)
  end

  @doc false
  @spec emit!(Macro.Env.t()) :: tuple()
  def emit!(caller) do
    args = Module.delete_attribute(caller.module, @pending_action)
    apply(Inline.Compiler, :create_action!, args)
  end

  @doc false
  @spec declaration_imports(Macro.Env.t()) :: Inline.remove_imports()
  def declaration_imports(caller) do
    modules =
      [
        Jido.Flow.DSL,
        Spark.Dsl,
        Jido.Flow.DSL.Extension,
        Jido.Flow.DSL.Macros,
        Jido.Flow.DSL.ParallelMacros,
        Jido.Flow.DSL.ChoiceMacros,
        Jido.Flow.DSL.IterateMacros
      ] ++
        for segments <- [
              [],
              ["Step"],
              ["Map"],
              ["Parallel"],
              ["Parallel", "ParallelAction"],
              ["Reduce"],
              ["Choice"],
              ["Choice", "Option"],
              ["Choice", "Otherwise"],
              ["Iterate"],
              ["Iterate", "State"],
              ["Invoke"],
              ["Handoff"],
              ["Output"]
            ],
            suffix <- [[], ["Options"]] do
          Module.concat([Jido.Flow.DSL.Extension, "Flow"] ++ segments ++ suffix)
        end

    for module <- modules,
        imports =
          Keyword.get(caller.functions, module, []) ++ Keyword.get(caller.macros, module, []),
        imports != [],
        do: {module, Enum.uniq(imports)}
  end

  defp merge_options!(options, body_options, caller, label) do
    MacroSupport.validate_options!(
      options,
      caller,
      "#{label} options must be a keyword list",
      "#{label} field"
    )

    MacroSupport.validate_options!(
      body_options,
      caller,
      "#{label} options must be a keyword list",
      "#{label} field"
    )

    options ++ body_options
  end

  defp validate_options!(options, caller, label, component_fields) do
    MacroSupport.validate_options!(
      options,
      caller,
      "#{label} options must be a keyword list",
      "#{label} field"
    )

    allowed = component_fields ++ [:inline, :do]

    allowed_message =
      if component_fields == [],
        do: "; use only inline: and do:",
        else: "; use only needs:, meta:, inline:, and do:"

    Config.allow_options!(
      options,
      allowed,
      caller,
      "#{label} field",
      allowed_message
    )
  end

  defp inline_options!(options, caller, label) do
    case Keyword.fetch(options, :inline) do
      :error ->
        []

      {:ok, inline_options} ->
        MacroSupport.validate_options!(
          inline_options,
          caller,
          "#{label} settings must be a keyword list",
          "#{label} setting"
        )

        Config.allow_options!(inline_options, @action_fields, caller, "#{label} setting")

        inline_options
    end
  end

  defp validate_sources!(bindings, caller, label) do
    for {:<-, _, [_pattern, source]} <- List.wrap(bindings) do
      validate_source!(source, caller, label)
    end

    :ok
  end

  defp validate_source!(source, caller, label) do
    with {:ok, expression} <- ValueParser.parse(source),
         :ok <- reject_source_operations(expression) do
      :ok
    else
      {:error, error} ->
        line =
          case source do
            {_, metadata, _} -> Keyword.get(metadata, :line, caller.line)
            _ -> caller.line
          end

        MacroSupport.compile_error!(
          %{caller | line: line},
          "#{label} binding source: #{error.message}"
        )
    end
  end

  defp reject_source_operations(%Jido.Expr{}) do
    {:error,
     Jido.Error.validation_error("Flow operations are not allowed; move the calculation into the inline body")}
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

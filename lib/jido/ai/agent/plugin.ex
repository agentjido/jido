defmodule Jido.AI.Agent.Plugin.Reasoning do
  @moduledoc false
  defstruct [:target, :defaults, :__spark_metadata__]
end

defmodule Jido.AI.Agent.Plugin.Tool do
  @moduledoc false
  defstruct [:target, :__spark_metadata__]
end

defmodule Jido.AI.Agent.Plugin do
  @moduledoc """
  Adds AI authoring data and static tool preparation to a Jido Agent.

  `use Jido.AI.Agent` adds this Plugin automatically. Add it directly to a
  core Agent only when you need the core `Jido.Agent` authoring surface.
  """

  alias Jido.Agent.Schema
  alias Jido.Error
  alias Jido.Codec.{Issue, Reference}
  alias Jido.Joi
  alias Spark.Dsl.Extension, as: SparkExtension

  @request_type "jido.ai.request"
  @response_type "jido.ai.response"

  @reasoning %Spark.Dsl.Entity{
    name: :__reasoning__,
    target: Jido.AI.Agent.Plugin.Reasoning,
    args: [:target],
    schema: [
      target: [type: :atom, required: true],
      defaults: [type: :any, default: %{}]
    ]
  }
  @tool %Spark.Dsl.Entity{
    name: :action,
    target: Jido.AI.Agent.Plugin.Tool,
    args: [:target],
    schema: [target: [type: :atom, required: true]]
  }
  @flow_tool %{@tool | name: :flow}
  @tools %Spark.Dsl.Section{name: :__tools__, entities: [@tool, @flow_tool]}
  @ai %Spark.Dsl.Section{name: :__ai__, entities: [@reasoning], sections: [@tools]}
  @reasoning_entity Module.concat([
                      __MODULE__,
                      Macro.camelize("__ai__"),
                      Macro.camelize("__reasoning__")
                    ])
  @tools_section Module.concat([
                   __MODULE__,
                   Macro.camelize("__tools__")
                 ])

  use Jido.Plugin,
    id: "jido.ai/agent",
    vsn: 1,
    sections: [@ai],
    option_keys: [agent: [:reasoning, :defaults, :tools]]

  defmacro ai(do: block) do
    caller = __CALLER__
    declarations = expressions(block)
    reasoning = Enum.filter(declarations, &match?({:reasoning, _, _}, &1))
    tools = Enum.filter(declarations, &match?({:tools, _, _}, &1))

    if Module.get_attribute(caller.module, :jido_ai_block_declared) do
      compile_error!(caller, caller.line, "An Agent can define only one ai block")
    end

    if length(reasoning) != 1 do
      compile_error!(caller, caller.line, "ai requires exactly one reasoning declaration")
    end

    if length(tools) > 1 do
      compile_error!(caller, caller.line, "An Agent can define at most one tools block")
    end

    if length(reasoning) + length(tools) != length(declarations) do
      compile_error!(caller, caller.line, "ai accepts only reasoning and tools declarations")
    end

    Module.put_attribute(caller.module, :jido_ai_block_declared, true)

    quote do
      require unquote(__MODULE__)
      unquote(__MODULE__).__ai__(do: unquote(block))
    end
  end

  defmacro tools(do: block) do
    caller = __CALLER__

    unless Enum.all?(expressions(block), &tool_declaration?/1) do
      compile_error!(caller, caller.line, "tools accepts only action or flow declarations")
    end

    quote do
      require unquote(@tools_section)
      unquote(@tools_section).__tools__(do: unquote(block))
    end
  end

  defmacro reasoning(do: body), do: inline_reasoning(body, __CALLER__)

  defmacro reasoning(target), do: referenced_reasoning(target, nil, __CALLER__)

  defmacro reasoning(target, do: body), do: referenced_reasoning(target, body, __CALLER__)

  @impl true
  def lower(dsl, config) do
    reasonings = SparkExtension.get_entities(dsl, [:__ai__])
    tools = SparkExtension.get_entities(dsl, [:__ai__, :__tools__])

    cond do
      config != %{} and (reasonings != [] or tools != []) ->
        Error.validation_result(:ambiguous_ai, [], "Use the AI DSL or provider data, not both")

      config != %{} ->
        normalize(config)

      length(reasonings) != 1 ->
        Error.validation_result(:reasoning_count, [:ai], "AI Agent requires exactly one reasoning Flow")

      true ->
        [reasoning] = reasonings

        normalize(%{
          reasoning: reasoning.target,
          defaults: reasoning.defaults,
          tools: Enum.map(tools, & &1.target)
        })
    end
  end

  @impl true
  def normalize(data) do
    with {:ok, data} <-
           Schema.fields(data, [:reasoning, :defaults, :tools], %{defaults: %{}, tools: []}),
         :ok <- validate_reasoning(data[:reasoning]),
         :ok <- reserved_defaults(data.defaults),
         {:ok, defaults} <- normalize_defaults(data.defaults, data.reasoning),
         :ok <- validate_tools(data.tools) do
      {:ok, %{reasoning: data.reasoning, defaults: defaults, tools: data.tools}}
    end
  end

  @impl true
  def derive_routes(%{reasoning: reasoning, defaults: defaults}) do
    [
      %{
        path: @request_type,
        as: :request,
        defaults: defaults,
        handler: %{kind: :flow, target: reasoning},
        state: %{source: :output, path: [:state]},
        reply: %{type: @response_type, from: %{source: :output, path: [:response]}}
      }
    ]
  end

  @impl true
  def prepare(_preparation, options) do
    tools = Keyword.get(options, :tools, [])
    defaults = Keyword.get(options, :defaults, %{})
    with :ok <- Jido.AI.Toolset.validate(tools), do: {:ok, %{tools: tools, defaults: defaults}}
  end

  @doc false
  @spec prepared_tools(map()) :: [module()]
  def prepared_tools(context) when is_map(context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{prepared: %{tools: tools}} -> tools
      _other -> []
    end
  end

  @doc false
  @spec prepared_defaults(map()) :: map()
  def prepared_defaults(context) when is_map(context) do
    case get_in(context, [:plugin_inputs, __MODULE__]) do
      %Jido.Plugin.Input{prepared: %{defaults: defaults}} -> defaults
      _other -> %{}
    end
  end

  @impl true
  def encode_authoring_data(data, registry) do
    with {:ok, data} <- normalize(data),
         {:ok, reasoning} <- Reference.encode(registry, :flow, data.reasoning),
         {:ok, defaults} <- encode_defaults(data.defaults, data.reasoning),
         {:ok, tools} <- encode_tools(data.tools, registry) do
      {:ok, %{"reasoning" => reasoning, "config" => defaults, "tools" => tools}}
    end
  end

  @impl true
  def decode_authoring_data(data, registry) do
    with :ok <- authoring_object(data),
         {:ok, reasoning} <- resolve_reference(data["reasoning"], :flow, registry, ["reasoning"]),
         {:ok, defaults} <- decode_defaults(data["config"], reasoning),
         {:ok, tools} <- decode_tools(data["tools"], registry) do
      normalize_authoring(reasoning, defaults, tools)
    end
  end

  defp validate_reasoning(target) do
    case Jido.Instruction.resolve(target) do
      {:ok, %{kind: :flow}} -> :ok
      _other -> Error.validation_result(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
    end
  rescue
    _error -> Error.validation_result(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
  catch
    _kind, _reason ->
      Error.validation_result(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
  end

  defp reserved_defaults(defaults) when is_map(defaults) and not is_struct(defaults) do
    if Map.has_key?(defaults, :input) or Map.has_key?(defaults, "input") do
      Error.validation_result(:reserved_default, [:defaults, :input], "AI input cannot be a reasoning default")
    else
      :ok
    end
  end

  defp reserved_defaults(_defaults),
    do: Error.validation_result(:invalid_defaults, [:defaults], "Reasoning defaults must be a map")

  defp normalize_defaults(defaults, reasoning) do
    case Jido.Flow.normalize_defaults(defaults, reasoning) do
      {:ok, defaults} ->
        {:ok, defaults}

      {:error, error} ->
        Error.validation_result(
          Map.get(error.details, :code, :invalid_defaults),
          [:defaults | Map.get(error.details, :path, [])],
          Exception.message(error),
          Map.delete(error.details, :path)
        )
    end
  end

  defp validate_tools(actions) do
    case Jido.AI.Toolset.validate(actions) do
      :ok ->
        :ok

      {:error, reason} ->
        Error.validation_result(:invalid_tools, [:tools], "Invalid Agent tools", %{reason: reason})
    end
  end

  defp encode_tools(tools, registry) do
    tools
    |> Enum.reduce_while({:ok, []}, fn tool, {:ok, encoded} ->
      case Reference.encode(registry, [:action, :flow], tool) do
        {:ok, reference} -> {:cont, {:ok, [reference | encoded]}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp authoring_object(data) when is_map(data) and not is_struct(data) do
    if Enum.sort(Map.keys(data)) == ~w(config reasoning tools) do
      :ok
    else
      issue(:invalid_document, [], "AI Plugin data requires reasoning, config, and tools")
    end
  end

  defp authoring_object(_data),
    do: issue(:invalid_document, [], "AI Plugin data must be an object")

  defp resolve_reference(value, kind, registry, path) do
    case Reference.decode(registry, value, kind) do
      {:ok, target} -> {:ok, target}
      {:error, error} -> {:error, reference_issue(error, path)}
    end
  end

  defp encode_defaults(defaults, reasoning) do
    case Jido.Flow.encode_defaults(defaults, reasoning) do
      {:ok, defaults} -> {:ok, defaults}
      {:error, error} -> {:error, flow_defaults_issue(error, ["config"])}
    end
  end

  defp decode_defaults(defaults, reasoning) do
    case Jido.Flow.decode_defaults(defaults, reasoning) do
      {:ok, defaults} -> {:ok, defaults}
      {:error, error} -> {:error, flow_defaults_issue(error, ["config"])}
    end
  end

  defp decode_tools(values, registry) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {value, index}, {:ok, tools} ->
      case resolve_reference(value, [:action, :flow], registry, ["tools", index]) do
        {:ok, tool} -> {:cont, {:ok, [tool | tools]}}
        {:error, _issue} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, tools} -> {:ok, Enum.reverse(tools)}
      error -> error
    end
  end

  defp decode_tools(_values, _registry),
    do: issue(:invalid_tools, ["tools"], "AI Plugin tools must be a list")

  defp normalize_authoring(reasoning, defaults, tools) do
    case normalize(%{reasoning: reasoning, defaults: defaults, tools: tools}) do
      {:ok, data} -> {:ok, data}
      {:error, error} -> {:error, normalize_issue(error)}
    end
  end

  defp normalize_issue(%Error.ValidationError{} = error) do
    path =
      Enum.map(error.path, fn
        :defaults -> "config"
        segment when is_atom(segment) -> Atom.to_string(segment)
        segment -> segment
      end)

    Issue.new(error.code, path, error.message, details: error.details)
  end

  defp reference_issue(error, path) do
    field = Map.get(error.details, :field)
    path = if is_binary(field), do: path ++ [field], else: path
    Issue.new(:reference, path, Exception.message(error), details: error.details)
  end

  defp flow_defaults_issue(error, path) do
    details = Map.get(error, :details, %{})
    default_path = details |> Map.get(:path, []) |> Enum.map(&json_segment/1)

    Issue.new(
      Map.get(details, :code, :invalid_defaults),
      path ++ default_path,
      Exception.message(error),
      details: Map.delete(details, :path)
    )
  end

  defp issue(code, path, message), do: {:error, Issue.new(code, path, message)}

  defp json_segment(segment) when is_atom(segment), do: Atom.to_string(segment)
  defp json_segment(segment), do: segment

  defp tool_declaration?({kind, _meta, [_target]}) when kind in [:action, :flow], do: true
  defp tool_declaration?(_declaration), do: false

  defp referenced_reasoning(target_ast, body, caller) do
    target =
      executable!(
        target_ast,
        :flow,
        "reasoning must reference a compiled Jido Flow module",
        caller
      )

    defaults = if is_nil(body), do: %{}, else: parse_defaults!(body, target, caller)

    quote line: caller.line do
      require unquote(@reasoning_entity)
      unquote(@reasoning_entity).__reasoning__(unquote(target), defaults: unquote(Macro.escape(defaults)))
    end
  end

  defp inline_reasoning(body, caller) do
    identity = quote do: [host: Jido.Agent, route: "jido.ai.request", role: :flow]

    compiled =
      Jido.Flow.Inline.compile!(
        identity,
        quote do
          [
            name: "reasoning",
            output_schema: Joi.object(%{state: Joi.map(), response: Joi.map()})
          ]
        end,
        body,
        caller
      )

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(@reasoning_entity)
      unquote(@reasoning_entity).__reasoning__(unquote(compiled.target_ast), defaults: %{})
    end
  end

  defp parse_defaults!(body, target, caller) do
    defaults = block!(body, "reasoning", caller)

    case Jido.Flow.normalize_defaults(defaults, target) do
      {:ok, defaults} ->
        if Map.has_key?(defaults, :input) do
          compile_error!(caller, caller.line, "reasoning input cannot be a default")
        else
          defaults
        end

      {:error, error} ->
        path = error.details |> Map.get(:path, []) |> Enum.map_join(".", &to_string/1)
        suffix = if path == "", do: "", else: " at #{path}"

        compile_error!(
          caller,
          caller.line,
          "reasoning configuration is invalid for #{inspect(target)}#{suffix}: #{Exception.message(error)}"
        )
    end
  end

  defp block!(body, scope, caller) do
    body
    |> expressions()
    |> Enum.reduce({%{}, MapSet.new()}, fn declaration, {config, names} ->
      {name, value, line} = declaration!(declaration, scope, caller)

      if MapSet.member?(names, name) do
        compile_error!(caller, line, "#{scope} defines #{name} more than once")
      end

      {Map.put(config, name, value), MapSet.put(names, name)}
    end)
    |> elem(0)
  end

  defp declaration!({name, metadata, [[do: body]]}, scope, caller) when is_atom(name) do
    {name, block!(body, "#{scope}.#{name}", caller), metadata[:line]}
  end

  defp declaration!({name, metadata, [value_ast]}, _scope, caller) when is_atom(name) do
    {name, literal!(name, value_ast, metadata[:line], caller), metadata[:line]}
  end

  defp declaration!(declaration, scope, caller) do
    compile_error!(
      caller,
      expression_line(declaration, caller.line),
      "#{scope} accepts only named literal values and nested blocks"
    )
  end

  defp literal!(name, value_ast, line, caller) do
    if Macro.quoted_literal?(value_ast) do
      {value, []} = Code.eval_quoted(value_ast, [], caller)
      value
    else
      compile_error!(caller, line, "#{name} requires a compile-time literal value")
    end
  end

  defp executable!(target_ast, kind, message, caller) do
    target = Macro.expand(target_ast, caller)

    with true <- is_atom(target) and target not in [nil, true, false],
         {:module, ^target} <- Code.ensure_compiled(target),
         {:ok, %{kind: ^kind}} <- Jido.Instruction.resolve(target) do
      target
    else
      _reason -> compile_error!(caller, caller.line, message)
    end
  end

  defp expressions({:__block__, _metadata, expressions}), do: expressions
  defp expressions(nil), do: []
  defp expressions(expression), do: [expression]

  defp expression_line({_name, metadata, _arguments}, fallback) when is_list(metadata),
    do: Keyword.get(metadata, :line, fallback)

  defp expression_line(_expression, fallback), do: fallback

  defp compile_error!(caller, line, description) do
    raise CompileError,
      file: caller.file,
      line: line || caller.line,
      description: description
  end
end

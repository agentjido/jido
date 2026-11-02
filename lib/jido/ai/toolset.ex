defmodule Jido.AI.Toolset do
  @moduledoc """
  The tools selected for one AI Agent.

  A Toolset is the capability allowlist owned by one Agent definition. Static
  tools are Action or Flow modules. Trusted runtime sources can add portable
  tools before request policy narrows that allowlist.
  """

  alias Jido.AI.ToolSource

  @type runtime_tool :: module() | ToolSource.tool()

  @doc "Returns the static tools from the protected Agent plugin input."
  @spec from_context(map()) :: [module()]
  def from_context(context) when is_map(context) do
    case get_in(context, [:plugin_inputs, Jido.AI.Agent.Plugin]) do
      %Jido.Plugin.Input{prepared: actions} when is_list(actions) -> actions
      _other -> []
    end
  end

  @doc "Validates an ordered Agent Toolset."
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(tools) when is_list(tools) do
    with :ok <- validate_modules(tools),
         :ok <- unique(tools, & &1) do
      unique(tools, & &1.name())
    end
  end

  def validate(_actions), do: {:error, :invalid_toolset}

  @doc "Returns the model tool names in declaration order."
  @spec names([runtime_tool()]) :: [String.t()]
  def names(tools) when is_list(tools), do: Enum.map(tools, &tool_name/1)

  @doc "Selects a request tool subset below the protected Agent allowlist."
  @spec select([runtime_tool()], map()) :: {:ok, map()} | {:error, term()}
  def select(tools, policy \\ %{})

  def select(tools, policy) when is_list(tools) and is_map(policy) do
    visible = field(policy, :visible) || []
    hidden = field(policy, :hidden) || []
    review = field(policy, :review) || []
    requirement = field(policy, :requirement) || :optional
    reason = field(policy, :reason)

    with :ok <- validate_runtime_tools(tools) do
      allowed = names(tools)

      with :ok <- validate_name_list(:visible, visible),
           :ok <- validate_name_list(:hidden, hidden),
           :ok <- validate_name_list(:review, review),
           :ok <- known_names(visible ++ hidden ++ review, allowed),
           :ok <- validate_requirement(requirement) do
        selected = select_tools(tools, visible, hidden, requirement)
        selected_names = names(selected)

        cond do
          requirement in [:required, :per_turn] and selected == [] ->
            {:error, {:tool_requirement_without_visible_tools, requirement}}

          Enum.any?(review, &(&1 not in selected_names)) ->
            {:error, {:review_tool_not_visible, Enum.find(review, &(&1 not in selected_names))}}

          true ->
            {:ok,
             %{
               tools: selected,
               actions: Enum.filter(selected, &action?/1),
               visible: selected_names,
               hidden: allowed -- selected_names,
               review: review,
               requirement: requirement,
               reason: reason
             }}
        end
      end
    end
  end

  def select(_actions, _policy), do: {:error, :invalid_tool_policy}

  @doc "Lowers semantic tool-use policy to one provider tool-choice value."
  @spec provider_tool_choice(atom(), non_neg_integer(), [runtime_tool()]) :: atom() | nil
  def provider_tool_choice(:disabled, _tool_rounds, _tools), do: :none
  def provider_tool_choice(_requirement, _tool_rounds, []), do: nil
  def provider_tool_choice(:optional, _tool_rounds, _tools), do: nil
  def provider_tool_choice(:required, 0, _tools), do: :required
  def provider_tool_choice(:required, _tool_rounds, _tools), do: :auto
  def provider_tool_choice(:per_turn, _tool_rounds, _tools), do: :required

  @doc "Checks whether one final answer satisfies semantic tool-use policy."
  @spec requirement_satisfied?(atom(), non_neg_integer(), [runtime_tool()]) :: boolean()
  def requirement_satisfied?(:required, 0, [_ | _]), do: false
  def requirement_satisfied?(:per_turn, _tool_rounds, [_ | _]), do: false
  def requirement_satisfied?(_requirement, _tool_rounds, _tools), do: true

  @doc "Builds ReqLLM definitions for an Agent Toolset."
  @spec definitions([runtime_tool()]) :: {:ok, [ReqLLM.Tool.t()]} | {:error, term()}
  def definitions(tools) when is_list(tools) do
    case validate_runtime_tools(tools) do
      :ok -> build_definitions(tools)
      error -> error
    end
  end

  @doc "Validates one portable model tool call against an Agent Toolset."
  @spec validate_call([runtime_tool()], map()) :: :ok | {:error, term()}
  def validate_call(tools, call) do
    with {:ok, _resolved} <- resolve_call(tools, call), do: :ok
  end

  @doc "Resolves one portable model tool call against an Agent Toolset."
  @spec resolve_call([runtime_tool()], map()) ::
          {:ok,
           %{
             id: String.t(),
             name: String.t(),
             arguments: map(),
             params: map(),
             executor: map(),
             tool: map(),
             description: String.t()
           }}
          | {:error, term()}
  def resolve_call(tools, %{id: id, name: name, arguments: arguments})
      when is_list(tools) and is_binary(id) and id != "" and is_binary(name) and
             is_map(arguments) do
    with {:ok, tool} <- fetch(tools, name),
         {:ok, params} <- decode_arguments(tool, arguments) do
      {:ok,
       %{
         id: id,
         name: name,
         arguments: arguments,
         params: params,
         executor: executor(tool),
         tool: identity(tool),
         description: tool_description(tool)
       }}
    end
  end

  def resolve_call(_actions, %{name: name}) when is_binary(name),
    do: {:error, {:unknown_tool, name}}

  def resolve_call(_actions, _call), do: {:error, :invalid_tool_call}

  @doc false
  @spec execution_boundary(map()) :: {:error, atom()}
  def execution_boundary(_arguments), do: {:error, :tool_must_run_in_agent_graph}

  defp validate_modules(tools) do
    case Enum.find(tools, &(not module_tool?(&1))) do
      nil -> :ok
      tool -> {:error, {:invalid_tool, tool}}
    end
  end

  defp module_tool?(target) when is_atom(target) and target not in [nil, true, false] do
    match?({:ok, _kind}, tool_kind(target))
  end

  defp module_tool?(_target), do: false

  defp action?(target), do: tool_kind(target) == {:ok, :action}

  defp unique(actions, key) do
    values = Enum.map(actions, key)
    if values == Enum.uniq(values), do: :ok, else: {:error, :duplicate_tools}
  end

  defp definition(target) when is_atom(target) do
    ReqLLM.Tool.new(
      name: target.name(),
      description: target.description() || "",
      parameter_schema: target.schema(),
      callback: {__MODULE__, :execution_boundary},
      strict: true
    )
  end

  defp definition(%{kind: :source} = tool), do: ToolSource.definition(tool)

  defp build_definitions(tools) do
    Enum.reduce_while(tools, {:ok, []}, fn tool, {:ok, definitions} ->
      case definition(tool) do
        {:ok, definition} -> {:cont, {:ok, [definition | definitions]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, definitions} -> {:ok, Enum.reverse(definitions)}
      error -> error
    end
  end

  defp fetch(tools, name) do
    case Enum.find(tools, &(tool_name(&1) == name)) do
      nil -> {:error, {:unknown_tool, name}}
      tool -> {:ok, tool}
    end
  end

  defp decode_arguments(target, arguments) when is_atom(target) do
    case Zoi.parse(target.schema(), arguments, coerce: true) do
      {:ok, params} -> target.validate_params(params)
      {:error, _reason} -> {:error, {:invalid_tool_arguments, target.name()}}
    end
  end

  defp decode_arguments(%{kind: :source} = tool, arguments) do
    case ToolSource.validate_input(tool, arguments) do
      {:ok, params} -> {:ok, params}
      {:error, _reason} -> {:error, {:invalid_tool_arguments, tool_name(tool)}}
    end
  end

  defp select_tools(_tools, _visible, _hidden, :disabled), do: []

  defp select_tools(tools, visible, hidden, _requirement) do
    tools
    |> Enum.filter(fn tool -> visible == [] or tool_name(tool) in visible end)
    |> Enum.reject(&(tool_name(&1) in hidden))
  end

  defp validate_runtime_tools(tools) do
    case Enum.find(tools, &(not runtime_tool?(&1))) do
      nil -> unique(tools, &tool_name/1)
      tool -> {:error, {:invalid_runtime_tool, tool}}
    end
  end

  defp runtime_tool?(%{kind: :source, source: %{module: module}} = tool)
       when is_atom(module) do
    is_binary(tool_name(tool))
  end

  defp runtime_tool?(tool), do: module_tool?(tool)

  defp tool_name(%{kind: :source, name: name}), do: name
  defp tool_name(target) when is_atom(target), do: target.name()

  defp tool_description(%{kind: :source, description: description}), do: description
  defp tool_description(target) when is_atom(target), do: target.description() || ""

  defp executor(%{kind: :source} = tool), do: ToolSource.executor(tool)
  defp executor(target) when is_atom(target), do: %{kind: tool_kind!(target), target: target}

  defp identity(%{kind: :source} = tool), do: ToolSource.identity(tool)

  defp identity(target) when is_atom(target) do
    kind = tool_kind!(target)
    manifest = target.__jido_authoring__()

    %{
      kind: kind,
      name: target.name(),
      id: manifest.id,
      vsn: manifest.vsn
    }
    |> Map.put(kind, Atom.to_string(target))
  end

  defp tool_kind(target) do
    case Jido.Instruction.resolve(target) do
      {:ok, %{kind: kind, target: ^target}} when kind in [:action, :flow] -> {:ok, kind}
      _other -> :error
    end
  end

  defp tool_kind!(target) do
    {:ok, kind} = tool_kind(target)
    kind
  end

  defp validate_name_list(_field, values) when is_list(values) do
    if List.improper?(values) do
      {:error, :invalid_tool_policy}
    else
      cond do
        Enum.any?(values, &(not is_binary(&1) or &1 == "")) -> {:error, :invalid_tool_policy}
        values != Enum.uniq(values) -> {:error, :duplicate_tool_policy_names}
        true -> :ok
      end
    end
  end

  defp validate_name_list(_field, _values), do: {:error, :invalid_tool_policy}

  defp known_names(requested, allowed) do
    case Enum.find(requested, &(&1 not in allowed)) do
      nil -> :ok
      name -> {:error, {:unknown_tool, name}}
    end
  end

  defp validate_requirement(requirement)
       when requirement in [:optional, :required, :per_turn, :disabled],
       do: :ok

  defp validate_requirement(requirement), do: {:error, {:invalid_tool_requirement, requirement}}

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

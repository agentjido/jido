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

  alias Jido.Agent.{Data, Error}
  alias Jido.Authoring.{Issue, Registry}
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

  use Jido.Plugin,
    id: "jido.ai/agent",
    vsn: 1,
    sections: [@ai],
    imports: [Jido.AI.Agent.DSL],
    option_keys: [agent: [:reasoning, :defaults, :tools]]

  @impl true
  def lower(dsl, config) do
    reasonings = SparkExtension.get_entities(dsl, [:__ai__])
    tools = SparkExtension.get_entities(dsl, [:__ai__, :__tools__])

    cond do
      config != %{} and (reasonings != [] or tools != []) ->
        Error.fail(:ambiguous_ai, [], "Use the AI DSL or provider data, not both")

      config != %{} ->
        normalize(config)

      length(reasonings) != 1 ->
        Error.fail(:reasoning_count, [:ai], "AI Agent requires exactly one reasoning Flow")

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
           Data.fields(data, [:reasoning, :defaults, :tools], %{defaults: %{}, tools: []}),
         :ok <- reasoning(data[:reasoning]),
         :ok <- reserved_defaults(data.defaults),
         {:ok, defaults} <- normalize_defaults(data.defaults, data.reasoning),
         :ok <- tools(data.tools) do
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
    with :ok <- Jido.AI.Toolset.validate(tools), do: {:ok, tools}
  end

  @impl true
  def encode_authoring_data(data, registry) do
    with {:ok, data} <- normalize(data),
         {:ok, reasoning} <- Registry.encode_reference(registry, :flow, data.reasoning),
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

  defp reasoning(target) do
    case Jido.Instruction.resolve(target) do
      {:ok, %{kind: :flow}} -> :ok
      _other -> Error.fail(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
    end
  rescue
    _error -> Error.fail(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
  catch
    _kind, _reason ->
      Error.fail(:invalid_reasoning, [:reasoning], "Reasoning must reference a Jido Flow")
  end

  defp reserved_defaults(defaults) when is_map(defaults) and not is_struct(defaults) do
    if Map.has_key?(defaults, :input) or Map.has_key?(defaults, "input") do
      Error.fail(:reserved_default, [:defaults, :input], "AI input cannot be a reasoning default")
    else
      :ok
    end
  end

  defp reserved_defaults(_defaults),
    do: Error.fail(:invalid_defaults, [:defaults], "Reasoning defaults must be a map")

  defp normalize_defaults(defaults, reasoning) do
    case Jido.Flow.normalize_defaults(defaults, reasoning) do
      {:ok, defaults} ->
        {:ok, defaults}

      {:error, error} ->
        Error.fail(
          Map.get(error.details, :code, :invalid_defaults),
          [:defaults | Map.get(error.details, :path, [])],
          Exception.message(error),
          Map.delete(error.details, :path)
        )
    end
  end

  defp tools(actions) do
    case Jido.AI.Toolset.validate(actions) do
      :ok ->
        :ok

      {:error, reason} ->
        Error.fail(:invalid_tools, [:tools], "Invalid Agent tools", %{reason: reason})
    end
  end

  defp encode_tools(tools, registry) do
    tools
    |> Enum.reduce_while({:ok, []}, fn tool, {:ok, encoded} ->
      case Registry.encode_reference(registry, [:action, :flow], tool) do
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
    case Registry.decode_reference(registry, value, kind) do
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

  defp normalize_issue(%Error{} = error) do
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
end

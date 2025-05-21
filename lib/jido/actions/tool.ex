defmodule Jido.Actions.Tool do
  @moduledoc """
  Provides functionality to convert Jido Execs into tool representations.

  This module allows Jido Execs to be easily integrated with AI systems
  like LangChain or Instructor by converting them into a standardized tool format.
  """

  alias Jido.Error

  @type tool :: %{
          name: String.t(),
          description: String.t(),
          function: (map(), map() -> {:ok, String.t()} | {:error, String.t()}),
          parameters_schema: map()
        }

  @doc """
  Converts a Jido Exec into a tool representation.

  ## Arguments

    * `action` - The module implementing the Jido.Action behavior.

  ## Returns

    A map representing the action as a tool, compatible with systems like LangChain.

  ## Examples

      iex> tool = Jido.Actions.Tool.to_tool(MyExec)
      %{
        name: "my_action",
        description: "Performs a specific task",
        function: #Function<...>,
        parameters_schema: %{...}
      }
  """
  @spec to_tool(module()) :: tool()
  def to_tool(action) when is_atom(action) do
    %{
      name: action.name(),
      description: action.description(),
      function: &execute_action(action, &1, &2),
      parameters_schema: build_parameters_schema(action.schema())
    }
  end

  @doc """
  Executes an action and formats the result for tool output.

  This function is typically used as the function value in the tool representation.
  """
  @spec execute_action(module(), map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def execute_action(action, params, context) do
    # Convert string keys to atom keys and handle type conversion based on schema
    converted_params = convert_params_using_schema(params, action.schema())
    safe_context = context || %{}

    case Jido.Exec.run(action, converted_params, safe_context) do
      {:ok, result} ->
        {:ok, Jason.encode!(result)}

      {:error, %Error{} = error} ->
        {:error, Jason.encode!(%{error: inspect(error)})}
    end
  end

  # Helper function to convert params using schema information
  def convert_params_using_schema(params, schema) do
    schema_keys = Keyword.keys(schema)

    Enum.reduce(schema_keys, %{}, fn key, acc ->
      string_key = to_string(key)

      if Map.has_key?(params, string_key) do
        value = params[string_key]
        schema_entry = Keyword.get(schema, key, [])
        type = Keyword.get(schema_entry, :type)

        converted_value =
          case {type, value} do
            {:float, val} when is_binary(val) ->
              case Float.parse(val) do
                {num, _} -> num
                :error -> val
              end

            {:integer, val} when is_binary(val) ->
              case Integer.parse(val) do
                {num, _} -> num
                :error -> val
              end

            _ ->
              value
          end

        Map.put(acc, key, converted_value)
      else
        acc
      end
    end)
  end

  @doc """
  Builds a parameters schema for the tool based on the action's schema.

  ## Arguments

    * `schema` - The NimbleOptions schema from the action.

  ## Returns

    A map representing the parameters schema in a format compatible with LangChain.
  """
  @spec build_parameters_schema(keyword()) :: map()
  def build_parameters_schema(schema) do
    properties =
      Map.new(schema, fn {key, opts} -> {to_string(key), parameter_to_json_schema(opts)} end)

    required =
      schema
      |> Enum.filter(fn {_key, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {key, _opts} -> to_string(key) end)

    %{
      type: "object",
      properties: properties,
      required: required
    }
  end

  @doc """
  Converts a NimbleOptions parameter definition to a JSON Schema representation.

  ## Arguments

    * `opts` - The options for a single parameter from the NimbleOptions schema.

  ## Returns

    A map representing the parameter in JSON Schema format.
  """
  @spec parameter_to_json_schema(keyword()) :: %{
          type: String.t(),
          description: String.t()
        }
  def parameter_to_json_schema(opts) do
    %{
      type: nimble_type_to_json_schema_type(Keyword.get(opts, :type)),
      description: Keyword.get(opts, :doc, "No description provided.")
    }
  end

  @doc """
  Converts a NimbleOptions type to a JSON Schema type.

  ## Arguments

    * `type` - The NimbleOptions type.

  ## Returns

    A string representing the equivalent JSON Schema type.
  """
  @spec nimble_type_to_json_schema_type(atom()) :: String.t()
  def nimble_type_to_json_schema_type(:string), do: "string"
  def nimble_type_to_json_schema_type(:number), do: "integer"
  def nimble_type_to_json_schema_type(:integer), do: "integer"
  def nimble_type_to_json_schema_type(:float), do: "string"
  def nimble_type_to_json_schema_type(:boolean), do: "boolean"
  def nimble_type_to_json_schema_type(:keyword_list), do: "object"
  def nimble_type_to_json_schema_type(:map), do: "object"
  def nimble_type_to_json_schema_type({:list, _}), do: "array"
  def nimble_type_to_json_schema_type({:map, _}), do: "object"
  def nimble_type_to_json_schema_type(_), do: "string"
end

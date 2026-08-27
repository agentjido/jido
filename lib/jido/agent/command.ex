defmodule Jido.Agent.Command do
  @moduledoc """
  Defines one command that an Agent strategy can process.

  A command can name an executable Action or Flow. It can also name an
  internal strategy operation that is not executable. Execution options are
  Agent policy and stay on the command. They are not stored in
  `Jido.Instruction` metadata.
  """

  alias Jido.Instruction

  @schema Zoi.struct(
            __MODULE__,
            %{
              action: Zoi.any(description: "Action, Flow, or internal strategy operation"),
              params: Zoi.map(description: "Command parameters") |> Zoi.default(%{}),
              context: Zoi.map(description: "Command context") |> Zoi.default(%{}),
              metadata: Zoi.map(description: "Invocation metadata") |> Zoi.default(%{}),
              opts: Zoi.any(description: "Agent execution policy options") |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for Agent commands."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Creates one Agent command."
  @spec new(term(), map() | keyword(), map() | keyword(), keyword(), map() | keyword()) ::
          {:ok, t()} | {:error, term()}
  def new(action, params \\ %{}, context \\ %{}, opts \\ [], metadata \\ %{}) do
    with :ok <- validate_action(action),
         {:ok, params} <- normalize_map(params, :params),
         {:ok, context} <- normalize_map(context, :context),
         :ok <- validate_opts(opts),
         {:ok, metadata} <- normalize_map(metadata, :metadata) do
      {:ok,
       %__MODULE__{
         action: action,
         params: params,
         context: context,
         metadata: metadata,
         opts: opts
       }}
    end
  end

  @doc "Creates one Agent command or raises."
  @spec new!(term(), map() | keyword(), map() | keyword(), keyword(), map() | keyword()) :: t()
  def new!(action, params \\ %{}, context \\ %{}, opts \\ [], metadata \\ %{}) do
    case new(action, params, context, opts, metadata) do
      {:ok, command} -> command
      {:error, reason} -> raise ArgumentError, "invalid Agent command: #{inspect(reason)}"
    end
  end

  @doc "Normalizes Agent command input into a list of commands."
  @spec normalize(term(), map() | keyword(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ []) do
    with {:ok, context} <- normalize_map(context, :context),
         :ok <- validate_opts(opts) do
      normalize_input(input, context, opts)
    end
  end

  defp normalize_input(inputs, context, opts) when is_list(inputs) do
    Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, commands} ->
      case normalize_single(input, context, opts) do
        {:ok, command} -> {:cont, {:ok, [command | commands]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, commands} -> {:ok, Enum.reverse(commands)}
      error -> error
    end
  end

  defp normalize_input(input, context, opts) do
    case normalize_single(input, context, opts) do
      {:ok, command} -> {:ok, [command]}
      error -> error
    end
  end

  defp normalize_single(%__MODULE__{} = command, context, opts) do
    with :ok <- validate_opts(command.opts) do
      {:ok,
       %{
         command
         | context: Map.merge(command.context || %{}, context),
           opts: Keyword.merge(command.opts, opts)
       }}
    end
  end

  defp normalize_single(%Instruction{} = instruction, context, opts) do
    new(
      instruction.target,
      instruction.params,
      Map.merge(instruction.context || %{}, context),
      opts,
      instruction.metadata
    )
  end

  defp normalize_single(action, context, opts) when is_atom(action) do
    new(action, %{}, context, opts)
  end

  defp normalize_single(%Jido.Flow{} = flow, context, opts) do
    new(flow, %{}, context, opts)
  end

  defp normalize_single({action, params}, context, opts) do
    new(action, params, context, opts)
  end

  defp normalize_single({action, params, item_context}, context, opts) do
    with {:ok, item_context} <- normalize_map(item_context, :context) do
      new(action, params, Map.merge(item_context, context), opts)
    end
  end

  defp normalize_single({action, params, item_context, item_opts}, context, opts) do
    with {:ok, item_context} <- normalize_map(item_context, :context),
         :ok <- validate_opts(item_opts) do
      new(action, params, Map.merge(item_context, context), Keyword.merge(item_opts, opts))
    end
  end

  defp normalize_single(input, _context, _opts), do: {:error, {:invalid_command, input}}

  @doc false
  @spec put_exec_defaults(t(), keyword()) :: t()
  def put_exec_defaults(%__MODULE__{} = command, defaults) when is_list(defaults) do
    merged_opts =
      defaults
      |> Enum.reverse()
      |> Enum.reduce(command.opts, fn
        {key, value}, acc when is_atom(key) -> Keyword.put_new(acc, key, value)
        _invalid, acc -> acc
      end)

    %{command | opts: merged_opts}
  end

  def put_exec_defaults(%__MODULE__{} = command, _defaults), do: command

  @doc false
  @spec run(t(), map(), keyword()) :: term()
  def run(%__MODULE__{} = command, runtime_context \\ %{}, exec_opts \\ [])
      when is_map(runtime_context) and is_list(exec_opts) do
    instruction_attrs = %{
      target: command.action,
      params: command.params,
      context: Map.merge(command.context, runtime_context),
      metadata: command.metadata
    }

    with {:ok, instruction} <- Instruction.new(instruction_attrs) do
      Jido.Exec.run(instruction, %{}, %{}, exec_opts)
    end
  end

  defp validate_action(action) when is_atom(action) and not is_nil(action), do: :ok
  defp validate_action(%Jido.Flow{}), do: :ok
  defp validate_action(action), do: {:error, {:invalid_action, action}}

  defp normalize_map(nil, _field), do: {:ok, %{}}
  defp normalize_map(value, _field) when is_map(value), do: {:ok, value}

  defp normalize_map(value, field) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, Map.new(value)}
    else
      {:error, {:invalid_map, field, value}}
    end
  end

  defp normalize_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid_options, opts}}
  end

  defp validate_opts(opts), do: {:error, {:invalid_options, opts}}
end

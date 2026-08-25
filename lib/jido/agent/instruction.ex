defmodule Jido.Agent.Instruction do
  @moduledoc """
  Compatibility helpers for Agent instructions.

  Jido 2.x supports both the `jido_action` v2 and v3 Instruction layouts. Use
  this module inside Agent strategies instead of reading dependency-owned
  Instruction fields directly.
  """

  alias Jido.ActionCompat
  alias Jido.Instruction

  @doc "Returns the detected `jido_action` major version."
  @spec jido_action_version() :: 2 | 3
  def jido_action_version, do: ActionCompat.major_version()

  @doc "Builds one dependency-compatible Instruction."
  @spec new(module() | atom(), map(), map(), keyword()) ::
          {:ok, Instruction.t()} | {:error, term()}
  def new(action, params \\ %{}, context \\ %{}, opts \\ []) do
    build_instruction(action, params, %{}, [], context, opts)
  end

  @doc "Builds one dependency-compatible Instruction or raises."
  @spec new!(module() | atom(), map(), map(), keyword()) :: Instruction.t()
  def new!(action, params \\ %{}, context \\ %{}, opts \\ []) do
    case new(action, params, context, opts) do
      {:ok, instruction} -> instruction
      {:error, reason} -> raise ArgumentError, "invalid instruction: #{inspect(reason)}"
    end
  end

  @doc "Normalizes Jido Agent module, tuple, list, and Instruction inputs."
  @spec normalize(term(), map(), keyword()) :: {:ok, [Instruction.t()]} | {:error, term()}
  def normalize(input, context \\ %{}, opts \\ [])

  def normalize(inputs, context, opts) when is_list(inputs) do
    with {:ok, context} <- normalize_map(context, :context),
         :ok <- validate_opts(opts) do
      Enum.reduce_while(inputs, {:ok, []}, fn input, {:ok, instructions} ->
        case normalize_single(input, context, opts) do
          {:ok, instruction} -> {:cont, {:ok, [instruction | instructions]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, instructions} -> {:ok, Enum.reverse(instructions)}
        error -> error
      end
    end
  end

  def normalize(input, context, opts) do
    with {:ok, context} <- normalize_map(context, :context),
         :ok <- validate_opts(opts),
         {:ok, instruction} <- normalize_single(input, context, opts) do
      {:ok, [instruction]}
    end
  end

  if ActionCompat.v3?() do
    @strategy_command_key :__jido_strategy_command__
    @exec_opts_key :__jido_exec_opts__

    @doc "Returns the Action or strategy command stored in an Instruction."
    @spec action(Instruction.t()) :: term()
    def action(%Instruction{target: Jido.Agent.Strategy.Command, metadata: metadata}) do
      Map.get(metadata, @strategy_command_key, Jido.Agent.Strategy.Command)
    end

    def action(%Instruction{target: target}), do: target

    @doc "Returns execution options stored by the Jido compatibility layer."
    @spec exec_opts(Instruction.t()) :: keyword()
    def exec_opts(%Instruction{metadata: metadata}) do
      normalize_opts(Map.get(metadata, @exec_opts_key, []))
    end

    @doc "Returns the optional Instruction identifier across both layouts."
    @spec id(Instruction.t()) :: term() | nil
    def id(%Instruction{metadata: metadata}), do: Map.get(metadata, :id)

    @doc "Runs an Instruction through the detected `jido_action` execution API."
    @spec run(Instruction.t(), keyword()) :: term()
    def run(%Instruction{} = instruction, exec_opts \\ []) when is_list(exec_opts) do
      Jido.Exec.run(instruction, %{}, %{}, exec_opts)
    end

    defp instruction_attrs(action, params, context, opts) do
      {target, metadata} = executable_target(action)

      %{
        target: target,
        params: params,
        context: context,
        metadata: Map.put(metadata, @exec_opts_key, opts)
      }
    end

    defp executable_target(action) do
      case ActionCompat.resolve(action) do
        {:ok, %{kind: :action, target: ^action}} ->
          {action, %{}}

        _error ->
          if is_elixir_module?(action) do
            {action, %{}}
          else
            {Jido.Agent.Strategy.Command, %{@strategy_command_key => action}}
          end
      end
    end

    defp is_elixir_module?(value) do
      value
      |> Atom.to_string()
      |> String.starts_with?("Elixir.")
    end

    defp put_exec_opts(%Instruction{} = instruction, opts) do
      metadata = Map.put(instruction.metadata, @exec_opts_key, opts)
      rebuild_instruction!(%{Map.from_struct(instruction) | metadata: metadata})
    end
  else
    @doc "Returns the Action or strategy command stored in an Instruction."
    @spec action(Instruction.t()) :: term()
    def action(%Instruction{action: action}), do: action

    @doc "Returns execution options stored by the Jido compatibility layer."
    @spec exec_opts(Instruction.t()) :: keyword()
    def exec_opts(%Instruction{opts: opts}), do: normalize_opts(opts)

    @doc "Returns the optional Instruction identifier across both layouts."
    @spec id(Instruction.t()) :: term() | nil
    def id(%Instruction{id: id}), do: id

    @doc "Runs an Instruction through the detected `jido_action` execution API."
    @spec run(Instruction.t(), keyword()) :: term()
    def run(%Instruction{} = instruction, exec_opts \\ []) when is_list(exec_opts) do
      Jido.Exec.run(instruction.action, instruction.params, instruction.context, exec_opts)
    end

    defp instruction_attrs(action, params, context, opts) do
      %{action: action, params: params, context: context, opts: opts}
    end

    defp put_exec_opts(%Instruction{} = instruction, opts) do
      rebuild_instruction!(%{Map.from_struct(instruction) | opts: opts})
    end
  end

  @doc false
  @spec put_exec_defaults(Instruction.t(), keyword()) :: Instruction.t()
  def put_exec_defaults(%Instruction{} = instruction, defaults) when is_list(defaults) do
    merged_opts =
      defaults
      |> Enum.reverse()
      |> Enum.reduce(exec_opts(instruction), fn
        {key, value}, acc when is_atom(key) -> Keyword.put_new(acc, key, value)
        _invalid, acc -> acc
      end)

    put_exec_opts(instruction, merged_opts)
  end

  def put_exec_defaults(%Instruction{} = instruction, _defaults), do: instruction

  defp normalize_single(%Instruction{} = instruction, context, opts) do
    with :ok <- validate_opts(opts) do
      instruction
      |> put_context(context)
      |> put_exec_opts(Keyword.merge(exec_opts(instruction), opts))
      |> then(&{:ok, &1})
    end
  end

  defp normalize_single(action, context, opts) when is_atom(action) do
    build_instruction(action, %{}, %{}, [], context, opts)
  end

  defp normalize_single({action, params}, context, opts) when is_atom(action) do
    build_instruction(action, params, %{}, [], context, opts)
  end

  defp normalize_single({action, params, item_context}, context, opts) when is_atom(action) do
    build_instruction(action, params, item_context, [], context, opts)
  end

  defp normalize_single({action, params, item_context, item_opts}, context, opts)
       when is_atom(action) do
    build_instruction(action, params, item_context, item_opts || [], context, opts)
  end

  defp normalize_single(input, _context, _opts), do: {:error, {:invalid_instruction, input}}

  defp build_instruction(action, params, item_context, item_opts, context, opts) do
    with {:ok, params} <- normalize_map(params, :params),
         {:ok, item_context} <- normalize_map(item_context, :context),
         :ok <- validate_opts(item_opts),
         :ok <- validate_opts(opts) do
      attrs =
        instruction_attrs(
          action,
          params,
          Map.merge(item_context, context),
          Keyword.merge(item_opts, opts)
        )

      Instruction.new(attrs)
    end
  end

  defp put_context(%Instruction{} = instruction, context) do
    attrs = Map.from_struct(instruction)
    merged_context = Map.merge(Map.get(attrs, :context) || %{}, context)

    attrs
    |> Map.put(:context, merged_context)
    |> rebuild_instruction!()
  end

  defp rebuild_instruction!(attrs) do
    case Instruction.new(attrs) do
      {:ok, instruction} -> instruction
      {:error, reason} -> raise ArgumentError, "invalid instruction: #{inspect(reason)}"
    end
  end

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: opts, else: []
  end

  defp normalize_opts(_opts), do: []

  defp normalize_map(nil, _field), do: {:ok, %{}}
  defp normalize_map(value, _field) when is_map(value), do: {:ok, value}

  defp normalize_map(value, _field) when is_list(value) do
    if Keyword.keyword?(value), do: {:ok, Map.new(value)}, else: {:error, {:invalid_map, value}}
  end

  defp normalize_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp validate_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid_options, opts}}
  end

  defp validate_opts(opts), do: {:error, {:invalid_options, opts}}
end

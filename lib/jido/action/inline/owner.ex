defmodule Jido.Action.Inline.Owner do
  @moduledoc false

  alias Jido.Action.Inline.Parser

  @doc false
  @spec ensure_compiling!(Macro.Env.t()) :: :ok
  def ensure_compiling!(caller) do
    unless is_atom(caller.module) and not is_nil(caller.module) and
             is_nil(caller.function) and Module.open?(caller.module) do
      Parser.error!(nil, caller, "inline Action compilation requires a compiling owner module")
    end

    :ok
  end

  @doc false
  @spec setup!(Macro.Env.t()) :: :ok
  def setup!(caller) do
    ensure_compiling!(caller)

    unless Module.get_attribute(caller.module, :__jido_inline_setup__) do
      reserve_function!(caller, {:__jido_inline_actions__, 0})
      Module.put_attribute(caller.module, :on_definition, {__MODULE__, :__on_definition__})
      Module.put_attribute(caller.module, :before_compile, __MODULE__)
      Module.put_attribute(caller.module, :__jido_inline_setup__, true)
    end

    :ok
  end

  @doc false
  @spec reserve_function!(Macro.Env.t(), {atom(), non_neg_integer()}) :: :ok
  def reserve_function!(caller, function),
    do: reserve_function!(caller, function, "inline Action")

  @doc false
  @spec reserve_function!(Macro.Env.t(), {atom(), non_neg_integer()}, String.t()) :: :ok
  def reserve_function!(caller, function, label) do
    labels = Module.get_attribute(caller.module, :__jido_inline_reserved_labels__) || %{}

    Module.put_attribute(
      caller.module,
      :__jido_inline_reserved_labels__,
      Map.put(labels, function, label)
    )

    if Module.defines?(caller.module, function), do: reserved_error!(caller, function)
    reserved = Module.get_attribute(caller.module, :__jido_inline_reserved__) || []

    Module.put_attribute(
      caller.module,
      :__jido_inline_reserved__,
      Enum.uniq([function | reserved])
    )

    :ok
  end

  @doc false
  @spec __on_definition__(Macro.Env.t(), atom(), atom(), list(), list(), term()) :: :ok
  def __on_definition__(caller, _kind, name, args, _guards, _body) do
    arity = length(args)
    defaults = Enum.count(args, &match?({:\\, _, [_, _]}, &1))
    reserved = Module.get_attribute(caller.module, :__jido_inline_reserved__) || []
    generated = Module.get_attribute(caller.module, :__jido_inline_generated__)

    for defined_arity <- (arity - defaults)..arity do
      function = {name, defined_arity}
      if function in reserved and generated != function, do: reserved_error!(caller, function)
    end

    :ok
  end

  @spec reserved_error!(Macro.Env.t(), {atom(), non_neg_integer()}) :: no_return()
  defp reserved_error!(caller, {name, arity} = function) do
    labels = Module.get_attribute(caller.module, :__jido_inline_reserved_labels__) || %{}
    label = Map.get(labels, function, "inline Action")

    Parser.error!(
      nil,
      caller,
      "reserved #{label} function #{name}/#{arity} cannot have user clauses"
    )
  end

  @doc false
  @spec validate_path!(term(), Macro.Env.t()) :: Jido.Action.Inline.path()
  def validate_path!(path, caller) do
    unless valid_path?(path) do
      Parser.error!(
        nil,
        caller,
        "inline Action identity must be a typed path with host, declaration, and role segments, got: #{inspect(path)}"
      )
    end

    path
  end

  defp valid_path?([{:host, _}, {_, _}, {_, _} | _] = path) do
    valid_segments?(path) and match?({:role, _}, List.last(path))
  end

  defp valid_path?(_), do: false

  defp valid_segments?([]), do: true

  defp valid_segments?([{kind, value} | rest]) when is_atom(kind) do
    ((is_atom(value) and not is_nil(value)) or is_binary(value) or is_integer(value)) and
      valid_segments?(rest)
  end

  defp valid_segments?(_), do: false

  @doc false
  @spec check_identity!(Jido.Action.Inline.path(), Macro.Env.t()) :: :ok
  def check_identity!(path, caller) do
    index = Module.get_attribute(caller.module, :__jido_inline_index__) || %{}

    if Map.has_key?(index, path),
      do: Parser.error!(nil, caller, "duplicate inline Action identity: #{inspect(path)}")

    :ok
  end

  @doc false
  @spec register!(Jido.Action.Inline.path(), module(), Macro.Env.t()) :: :ok
  def register!(path, target, caller) do
    index = Module.get_attribute(caller.module, :__jido_inline_index__) || %{}
    index = Map.put(index, path, target)
    Module.put_attribute(caller.module, :__jido_inline_index__, index)

    if Module.defines?(caller.module, {:__jido_inline_actions__, 0}) do
      Module.delete_definition(caller.module, {:__jido_inline_actions__, 0})
      Code.eval_quoted(index_definition(index), [], caller)
    end

    :ok
  end

  @doc false
  defmacro __before_compile__(caller) do
    index = Module.get_attribute(caller.module, :__jido_inline_index__) || %{}
    index_definition(index)
  end

  defp index_definition(index) do
    quote generated: true do
      @__jido_inline_generated__ {:__jido_inline_actions__, 0}
      @doc false
      @spec __jido_inline_actions__() :: %{optional(Jido.Action.Inline.path()) => module()}
      def __jido_inline_actions__, do: unquote(Macro.escape(index))
      Module.delete_attribute(__MODULE__, :__jido_inline_generated__)
    end
  end

  @doc false
  @spec target!(module(), Jido.Action.Inline.path()) :: module()
  def target!(owner, path) do
    if is_atom(owner) and not is_nil(owner) and Module.open?(owner) do
      raise ArgumentError, "inline Action lookup is available only after the owner compiles"
    end

    with true <- is_atom(owner) and not is_nil(owner) and valid_path?(path),
         true <- Code.ensure_loaded?(owner),
         true <- function_exported?(owner, :__jido_inline_actions__, 0),
         {:ok, target} <- Map.fetch(owner.__jido_inline_actions__(), path) do
      target
    else
      _ ->
        raise ArgumentError,
              "unknown inline Action identity in #{inspect(owner)}: #{inspect(path)}"
    end
  end
end

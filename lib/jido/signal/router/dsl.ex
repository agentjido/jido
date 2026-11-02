defmodule Jido.Signal.Router.DSL do
  @moduledoc false

  alias Jido.Signal.Router
  alias Jido.Signal.Router.Index

  @doc """
  Declares one route.

  Accepts the same path and target specifications as `Jido.Signal.Router.new/1`.
  The path may be a string or a `use Jido.Signal` module. Match predicates
  must be `{module, function, args}` MFA values. Compiled route values must be
  static module data.
  """
  @spec route(term(), term()) :: Macro.t()
  defmacro route(path, target) do
    store_route(path, [target], __CALLER__)
  end

  @doc "Declares one route with a match predicate or priority."
  @spec route(term(), term(), term()) :: Macro.t()
  defmacro route(path, match_or_target, target_or_priority) do
    store_route(path, [match_or_target, target_or_priority], __CALLER__)
  end

  @doc "Declares one route with a match predicate and priority."
  @spec route(term(), term(), term(), term()) :: Macro.t()
  defmacro route(path, match, target, priority) do
    store_route(path, [match, target, priority], __CALLER__)
  end

  @doc "Compiles accumulated `route` declarations into Router accessors."
  @spec __before_compile__(Macro.Env.t()) :: Macro.t()
  defmacro __before_compile__(env) do
    routes_with_lines =
      env.module
      |> Module.get_attribute(:__jido_signal_routes__)
      |> List.wrap()
      |> Enum.reverse()

    specs = Enum.map(routes_with_lines, &elem(&1, 0))

    ensure_path_modules_compiled(specs)
    routes = normalize_compiled_routes!(routes_with_lines, env)
    router = Index.new(routes)

    quote do
      @doc "Returns the compiled Router value."
      @spec router() :: Jido.Signal.Router.t()
      def router, do: unquote(Macro.escape(router))

      @doc "Returns Routes in declaration order."
      @spec routes() :: [Jido.Signal.Router.Route.t()]
      def routes, do: unquote(Macro.escape(routes))

      @doc "Returns targets for a Signal from this Router."
      @spec route(Jido.Signal.t()) :: {:ok, [term()]} | {:error, term()}
      def route(signal), do: Jido.Signal.Router.route(router(), signal)
    end
  end

  defp store_route(path, [target], caller) do
    quote line: caller.line do
      @__jido_signal_routes__ {{unquote(path), unquote(target)}, unquote(caller.line)}
    end
  end

  defp store_route(path, [match_or_target, target_or_priority], caller) do
    quote line: caller.line do
      @__jido_signal_routes__ {{unquote(path), unquote(match_or_target),
                                unquote(target_or_priority)}, unquote(caller.line)}
    end
  end

  defp store_route(path, [match, target, priority], caller) do
    quote line: caller.line do
      @__jido_signal_routes__ {{unquote(path), unquote(match), unquote(target),
                                unquote(priority)}, unquote(caller.line)}
    end
  end

  defp ensure_path_modules_compiled(specs) do
    Enum.each(specs, fn spec ->
      case route_path(spec) do
        module when is_atom(module) -> Code.ensure_compiled(module)
        _path -> :ok
      end
    end)
  end

  defp route_path(spec) when is_tuple(spec) and tuple_size(spec) >= 2, do: elem(spec, 0)
  defp route_path(_spec), do: nil

  defp normalize_compiled_routes!(routes_with_lines, env) do
    Enum.map(routes_with_lines, fn {spec, line} ->
      validate_compiled_match!(spec, env, line)
      validate_static_route!(spec, env, line)

      case Router.normalize(spec) do
        {:ok, [route]} -> route
        {:error, error} -> compile_error!(env, line, Exception.message(error))
      end
    end)
  end

  defp validate_compiled_match!({_path, _target, priority}, _env, _line)
       when is_integer(priority),
       do: :ok

  defp validate_compiled_match!({_path, match, _target}, env, line),
    do: validate_mfa!(match, env, line)

  defp validate_compiled_match!({_path, match, _target, _priority}, env, line),
    do: validate_mfa!(match, env, line)

  defp validate_compiled_match!(_spec, _env, _line), do: :ok

  defp validate_mfa!({module, function, args}, _env, _line)
       when is_atom(module) and is_atom(function) and is_list(args),
       do: :ok

  defp validate_mfa!(_match, env, line) do
    compile_error!(env, line, "route match must be a {Module, :function, args} MFA")
  end

  defp validate_static_route!(spec, env, line) do
    {_escaped, runtime_process_value?} =
      spec
      |> Macro.escape()
      |> Macro.prewalk(false, fn value, found? ->
        {value, found? or is_pid(value) or is_port(value) or is_reference(value)}
      end)

    if runtime_process_value? do
      compile_error!(env, line, "compiled route values must be static module data")
    end
  rescue
    ArgumentError ->
      compile_error!(env, line, "compiled route values must be static module data")
  end

  defp compile_error!(caller, line, description) do
    raise CompileError, file: caller.file, line: line, description: description
  end
end

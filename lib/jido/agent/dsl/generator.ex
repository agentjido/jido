defmodule Jido.Agent.DSL.Generator do
  @moduledoc false

  def function(interface, name, mode, arity) do
    arguments = arguments(interface, mode, arity)
    variables = variables(arguments)
    config = Macro.escape(interface)

    body =
      case mode do
        :call ->
          [server | values] = variables
          quote do: Jido.Agent.Interface.call(unquote(config), unquote(server), unquote(values))

        :signal ->
          quote do: Jido.Agent.Interface.signal(unquote(config), unquote(variables))

        :signal! ->
          quote do: Jido.Agent.Interface.signal!(unquote(config), unquote(variables))
      end

    types = Enum.map(arguments, &argument_type/1)

    quote do
      @doc unquote(documentation(interface, mode, arguments))
      @spec unquote(name)(unquote_splicing(types)) :: unquote(result_type(mode))
      def unquote(name)(unquote_splicing(variables)), do: unquote(body)
    end
  end

  defp arguments(interface, mode, arity) do
    offset = if mode == :call, do: 1, else: 0
    count = arity - offset
    fields = Enum.map(Enum.take(interface.fields, count), &{:input, &1})

    fields =
      cond do
        count > length(interface.fields) ->
          fields ++ [{:options, :opts}]

        count > interface.required ->
          List.update_at(fields, -1, fn {_, field} ->
            {:input_or_options, String.to_atom("#{field}_or_opts")}
          end)

        true ->
          fields
      end

    if mode == :call, do: [{:server, :server} | fields], else: fields
  end

  defp variables(arguments) do
    {variables, _used} =
      arguments
      |> Enum.with_index(1)
      |> Enum.map_reduce(MapSet.new(), fn {{_kind, name}, index}, used ->
        name = if variable_name?(name), do: name, else: String.to_atom("input_#{index}")
        name = available_name(name, used)
        {Macro.var(name, __MODULE__), MapSet.put(used, name)}
      end)

    variables
  end

  defp variable_name?(name) do
    text = Atom.to_string(name)

    not String.starts_with?(text, "_") and
      match?({:ok, {^name, _, nil}}, Code.string_to_quoted(text))
  end

  defp available_name(name, used, suffix \\ 1) do
    candidate = if suffix == 1, do: name, else: String.to_atom("#{name}_#{suffix}")

    if MapSet.member?(used, candidate),
      do: available_name(name, used, suffix + 1),
      else: candidate
  end

  defp argument_type({:server, _}), do: quote(do: Jido.AgentServer.server())
  defp argument_type({:options, _}), do: quote(do: keyword())
  defp argument_type(_argument), do: quote(do: term())

  defp result_type(:call), do: quote(do: {:ok, Jido.Agent.t()} | {:error, term()})
  defp result_type(:signal), do: quote(do: {:ok, Jido.Signal.t()} | {:error, term()})
  defp result_type(:signal!), do: quote(do: Jido.Signal.t())

  defp documentation(interface, mode, arguments) do
    fields =
      interface.fields
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {field, index} ->
        requirement = if index < interface.required, do: "required", else: "optional"
        "`#{inspect(field)}` (#{requirement})"
      end)

    fields = if fields == "", do: "None; supply payload fields through `input`.", else: fields

    options_form =
      if Enum.any?(arguments, &match?({:input_or_options, _}, &1)) do
        "The last argument accepts either its positional input value or a keyword options list."
      else
        "Options use a final keyword list. Shorter arities omit optional inputs or options."
      end

    """
    #{summary(mode, interface.path)}

    Positional inputs, in order: #{fields}

    #{options_form}
    Omitted optional inputs remain absent. Route defaults supply absent fields
    during execution with a shallow merge. Explicit `nil`, `false`, and zero
    override defaults.

    Options:

    * `:input` — a map of additional payload fields. A field cannot be supplied
      both positionally and through this map.
    * `:signal` — Signal envelope options, including `:source`, `:id`, and
      `:subject`. Signal type and data cannot be replaced through these options.
    #{runtime_options(mode)}

    Raw input values are packaged without coercion or executable validation.
    Plugins prepare input during command execution, then the Action or Flow
    validates its input. Constructing a Signal does not execute a command.
    Unknown or duplicate options are errors.
    """
  end

  defp summary(:call, path) do
    """
    Sends `#{path}` to an Agent Server and waits for its result.

    Returns `{:ok, committed_agent}` or `{:error, reason}`. The first argument
    is a Server reference accepted by `Jido.AgentServer.call/3`. Direct
    evaluation of an immutable Agent uses `Jido.Agent.cmd/3` with a Signal.
    """
  end

  defp summary(:signal, path),
    do: "Builds a `#{path}` Signal. Returns `{:ok, signal}` or `{:error, reason}`."

  defp summary(:signal!, path),
    do: "Builds a `#{path}` Signal. Returns the Signal or raises on invalid options or envelope."

  defp runtime_options(:call) do
    """
    * `:context` — caller context for this Turn; it is not added to Signal data.
    * `:timeout` — caller wait limit, as accepted by `Jido.AgentServer.call/3`.

    Server call exits propagate, including caller timeout. A timeout stops
    waiting; it does not cancel a Turn that has already started.
    """
  end

  defp runtime_options(_mode),
    do: "\n`:context` and `:timeout` are accepted only by the live call helper."
end

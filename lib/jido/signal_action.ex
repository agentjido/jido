defmodule Jido.SignalAction do
  @moduledoc """
  Defines an Action and its input Signal in one module.

  The input schema checks both Signal data and Action parameters. The Action
  uses the normal `c:Jido.Action.run/2` callback and `Jido.Exec` validation.

      defmodule MyApp.CreateThread do
        use Jido.SignalAction,
          name: "create_thread",
          description: "Create a named chat thread",
          vsn: 1,
          input: [type: "chat.thread.create", schema: Zoi.object(%{name: Zoi.string()})],
          output: [type: "chat.thread.created", schema: Zoi.object(%{id: Zoi.string()})]

        @impl Jido.Action
        def run(data, %{client: client}) do
          MyApp.Threads.create(client, data)
        end
      end

  Define `input` and Signal `output` with keyword options for `use Jido.Signal`.
  Each definition supplies the full `type` string and its `schema`. It can also
  supply `dataschema`, `default_source`, and `datacontenttype`. Tuple forms are
  not supported. An existing Signal definition module can supply either contract.
  `output` also accepts a normal Action output schema. An omitted output keeps
  the normal Action output contract.

  `new/2` builds a validated input Signal. `reply/3` checks output data and
  builds a new Signal. A reply keeps the request trace and uses the request ID
  as its causation ID. The caller supplies the source when the Signal
  definition has no default source. These functions do not dispatch Signals.
  Errors keep the normal Action error contract. There is no automatic failure
  Signal.

  ## Agent routes

      routes do
        route MyApp.CreateThread
        # Or use a handler that returns work for execution after commit:
        # route MyApp.CreateThread, via: MyApp.ExecuteAfterCommit
      end

  A module route uses the input Signal type and selects the Action. It has the
  same state and directive contract as an ordinary Action route. Use `reply/3`
  when a handler must turn result data into a Signal. `via:` selects the given
  handler instead. It does not run the SignalAction or change commit timing.
  """

  alias Jido.{Error, Signal}

  @doc "Defines a SignalAction with static input and output schemas."
  defmacro __using__(opts) do
    quote location: :keep do
      @signal_action Jido.SignalAction.__compile__!(unquote(opts), __ENV__)

      use Jido.Action, @signal_action.action

      @doc "Returns the contract version."
      @spec vsn() :: pos_integer()
      def vsn, do: @signal_action.vsn

      @doc false
      def __signal_action__, do: @signal_action

      @doc false
      def __signal_definition__, do: @signal_action.input

      @doc "Returns the input Signal type."
      @spec type() :: String.t()
      def type, do: @signal_action.input.type

      @doc "Returns the default input Signal source."
      @spec default_source() :: String.t() | nil
      def default_source, do: @signal_action.input.default_source

      @doc "Returns the input data content type."
      @spec datacontenttype() :: String.t() | nil
      def datacontenttype, do: @signal_action.input.datacontenttype

      @doc "Returns the input data schema URI."
      @spec dataschema() :: String.t() | nil
      def dataschema, do: @signal_action.input.dataschema

      @doc "Validates input Signal data with the shared input schema."
      @spec validate_data(term()) :: Zoi.result()
      def validate_data(data), do: Zoi.parse(schema(), data)

      @doc "Builds an input Signal without execution or dispatch."
      @spec new(term(), keyword() | map()) :: {:ok, Jido.Signal.t()} | {:error, term()}
      def new(data \\ %{}, opts \\ []) do
        with {:ok, data} <- validate_data(data),
             do: Jido.SignalAction.__build__(@signal_action.input, data, opts)
      end

      @doc "Builds an input Signal or raises its validation error."
      @spec new!(term(), keyword() | map()) :: Jido.Signal.t() | no_return()
      def new!(data \\ %{}, opts \\ []) do
        case new(data, opts) do
          {:ok, signal} -> signal
          {:error, errors} when is_list(errors) -> raise Zoi.ParseError, errors: errors
          {:error, reason} -> raise ArgumentError, "invalid Signal: #{inspect(reason)}"
        end
      end

      @doc "Builds a correlated output Signal without dispatch."
      @spec reply(Jido.Signal.t(), map(), keyword() | map()) ::
              {:ok, Jido.Signal.t()} | {:error, term()}
      def reply(request, data, opts \\ []),
        do: Jido.SignalAction.reply(__MODULE__, request, data, opts)
    end
  end

  @doc "Returns true when a module defines a SignalAction."
  @spec defined?(term()) :: boolean()
  def defined?(module) when is_atom(module),
    do: Code.ensure_loaded?(module) and function_exported?(module, :__signal_action__, 0)

  def defined?(_value), do: false

  @doc "Builds a validated output Signal and preserves request correlation."
  @spec reply(module(), Signal.t(), map(), keyword() | map()) ::
          {:ok, Signal.t()} | {:error, term()}
  def reply(module, request, data, opts \\ []) do
    with {:ok, request} <- request(module, request),
         {:ok, definition} <- output(module),
         :ok <- plain_output(data),
         {:ok, data} <- module.validate_output(data),
         {:ok, signal} <- __build__(definition, data, opts),
         {:ok, signal} <- correlate(signal, request) do
      {:ok, signal}
    end
  end

  @doc false
  def route_type!(module, env) do
    Code.ensure_compiled!(module)

    if defined?(module),
      do: Macro.compile_apply(module, :type, [], env),
      else: raise(ArgumentError, "Module route requires a Jido.SignalAction")
  end

  @doc false
  def __compile__!(opts, env) do
    unless Keyword.keyword?(opts) and Enum.uniq(Keyword.keys(opts)) == Keyword.keys(opts),
      do: compile_error!(env, "SignalAction requires unique keyword options")

    unknown = Keyword.keys(opts) -- [:name, :description, :vsn, :input, :output]
    if unknown != [], do: compile_error!(env, "Unknown SignalAction options: #{inspect(unknown)}")

    for key <- [:name, :description, :vsn, :input] do
      unless Keyword.has_key?(opts, key),
        do: compile_error!(env, "SignalAction requires #{inspect(key)}")
    end

    vsn = opts[:vsn]

    unless is_integer(vsn) and vsn > 0,
      do: compile_error!(env, "SignalAction :vsn must be a positive integer")

    unless is_binary(opts[:description]) and String.trim(opts[:description]) != "",
      do: compile_error!(env, "SignalAction :description must be a non-blank string")

    input = definition!(opts[:input], env)
    {output, output_schema} = output!(Keyword.get(opts, :output, []), env)

    %{
      vsn: vsn,
      input: input,
      output: output,
      action: [
        name: opts[:name],
        description: opts[:description],
        schema: input.schema,
        output_schema: output_schema
      ]
    }
  end

  @doc false
  def __build__(definition, data, opts) do
    defaults =
      %{"source" => definition.default_source, "datacontenttype" => definition.datacontenttype}
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    with {:ok, attrs} <- Signal.__normalize_definition_attrs__(opts, defaults) do
      attrs
      |> Map.put("type", definition.type)
      |> Map.put("dataschema", definition.dataschema)
      |> Map.put("data", data)
      |> Signal.new()
    end
  end

  defp definition!(module, env) when is_atom(module) and module not in [nil, true, false] do
    ensure_compiled!(module, env)
    fields = [:type, :schema, :dataschema, :default_source, :datacontenttype]

    if Enum.all?(fields, &function_exported?(module, &1, 0)) do
      fields
      |> Enum.map(&{&1, Macro.compile_apply(module, &1, [], env)})
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> definition!(env)
    else
      compile_error!(env, "Expected a Signal definition module, got: #{inspect(module)}")
    end
  end

  defp definition!(opts, env) when is_list(opts),
    do: Signal.__compile_definition__(opts, env)

  defp definition!(_value, env),
    do: compile_error!(env, "Expected Signal keyword options or a Signal definition module")

  defp ensure_compiled!(module, env) do
    Code.ensure_compiled!(module)
  rescue
    ArgumentError -> compile_error!(env, "Cannot load Signal definition #{inspect(module)}")
  end

  defp output!(value, env) when is_atom(value), do: signal_output!(value, env)

  defp output!(value, env) when is_tuple(value),
    do: compile_error!(env, "Expected Signal keyword options or a Signal definition module")

  defp output!([_ | _] = value, env), do: signal_output!(value, env)
  defp output!(schema, _env), do: {nil, schema}

  defp signal_output!(value, env) do
    definition = definition!(value, env)
    {definition, definition.schema}
  end

  defp request(module, %Signal{} = request) do
    with {:ok, request} <- Zoi.parse(Signal.schema(), request) do
      if request.type == module.type() and request.dataschema == module.dataschema(),
        do: {:ok, request},
        else:
          {:error,
           Error.validation_error("Request does not match the input Signal definition",
             field: :signal,
             subject: module
           )}
    end
  end

  defp request(module, _value),
    do: {:error, Error.validation_error("Expected a request Signal", subject: module)}

  defp output(module) do
    case module.__signal_action__().output do
      nil -> {:error, Error.validation_error("Action has no output Signal", subject: module)}
      definition -> {:ok, definition}
    end
  end

  defp plain_output(data) when is_map(data) and not is_struct(data), do: :ok

  defp plain_output(_data),
    do: {:error, Error.validation_error("Output Signal data must be a plain map", field: :data)}

  defp correlate(signal, request) do
    with {:ok, _request, trace} <- Signal.Trace.ensure(request),
         {:ok, signal} <- Signal.Trace.put(%{signal | id: Signal.ID.generate!()}, trace),
         do: Signal.put_context(signal, "jidocausationid", request.id)
  end

  defp compile_error!(env, description),
    do: raise(CompileError, file: env.file, line: env.line, description: description)
end

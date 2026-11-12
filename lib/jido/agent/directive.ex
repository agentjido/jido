defmodule Jido.Agent.Directive do
  alias Jido.Joi

  @moduledoc """
  Runtime work returned by an Agent executable turn.

  The terminal Action or Flow output is complete next Agent state. Plugin-owned
  fields must remain unchanged until their owning Plugin reduces the batch.
  Plugin-owned Directives can change their owner's state during reduction and
  request runtime work after commit. `Jido.AgentServer` commits the candidate
  before it dispatches runtime work. A dispatch failure does not undo that
  commit. A later Agent state change must enter through a Signal.

  Return `{:ok, state, directives}` from an Action.
  Flow preserves the batch from all successful executed components. A failed
  Flow returns no executable batch. Core validates every Directive and the
  complete state before commit. The third element is an optional proper list
  for both direct Actions and Flow composition.

  Directives request runtime operations or work that must happen after commit.
  An Action or Flow can also perform synchronous I/O before returning its
  complete state. That I/O is outside the Agent state transaction and is not
  undone if the Turn fails.

  A custom Directive uses this module as a behavior. `use Jido.Agent.Directive`
  supplies a default `validate/1` callback. The default applies `schema/0` when
  the Directive module defines it. A Directive can override `validate/1` when
  it needs another validation rule.
  """

  alias __MODULE__.{Emit, Reply}

  alias Jido.Agent.Schema
  alias Jido.Error
  alias Jido.Signal
  alias Jido.Signal.Context, as: SignalContext

  @callback validate(directive :: struct()) :: {:ok, struct()} | {:error, term()}

  @doc "Defines a self-validating custom Agent Directive."
  defmacro __using__(opts) do
    built_in? = Keyword.get(opts, :built_in, false)

    quote location: :keep, bind_quoted: [built_in?: built_in?] do
      @behaviour Jido.Agent.Directive

      if built_in? do
        @doc false
        def __jido_builtin_directive__, do: true
      end

      @impl Jido.Agent.Directive
      # `use` can precede `defstruct`; do not expand the struct here.
      def validate(%{__struct__: __MODULE__} = directive) do
        if function_exported?(__MODULE__, :schema, 0) do
          Jido.Agent.Directive.parse(apply(__MODULE__, :schema, []), Map.from_struct(directive))
        else
          {:ok, directive}
        end
      end

      def validate(value) do
        {:error,
         Jido.Error.validation_error("Expected a #{inspect(__MODULE__)} Directive",
           details: %{directive: value}
         )}
      end

      defoverridable validate: 1
    end
  end

  @type t :: struct()

  @doc "Validates one built-in or custom Agent Directive."
  @spec validate(struct()) :: {:ok, struct()} | {:error, term()}
  def validate(%{__struct__: module, signal: %Signal{} = signal} = directive)
      when module in [Emit, Reply] do
    with {:ok, signal} <- parse(Signal.schema(), signal),
         {:ok, extensions} <- normalize_context(signal.extensions),
         {:ok, directive} <-
           directive
           |> Map.from_struct()
           |> Map.put(:signal, %{signal | extensions: extensions})
           |> then(&parse(module.schema(), &1)),
         :ok <- validate_reply_causation(directive) do
      {:ok, directive}
    end
  end

  def validate(%{__struct__: module} = directive)
      when module in [Emit, Reply] do
    {:error,
     Jido.Error.validation_error("Agent Signal Directive requires a Jido.Signal",
       details: %{directive: directive}
     )}
  end

  def validate(%{__struct__: module} = directive), do: validate_custom(module, directive)

  def validate(value) do
    {:error,
     Jido.Error.validation_error("Unknown Agent Directive",
       details: %{directive: value}
     )}
  end

  @doc false
  @spec parse(Joi.schema(), term()) :: {:ok, term()} | {:error, Exception.t()}
  def parse(schema, value) do
    with {:error, issues} <- Joi.parse(schema, value), do: invalid_schema(issues)
  end

  defp invalid_schema(issues) do
    issues =
      Enum.map(issues, fn issue ->
        %{code: Joi.error_code(issue), path: Joi.error_path(issue), message: Joi.error_message(issue)}
      end)

    Error.validation_result(:invalid_directive, [], "Agent Directive does not match its schema", %{
      issues: issues
    })
  end

  defp normalize_context(extensions) do
    with {:error, reason} <- SignalContext.normalize(extensions) do
      Error.validation_result(:invalid_directive, [:signal, :extensions], "Signal context is invalid", %{
        reason: reason
      })
    end
  end

  defp validate_custom(module, directive) do
    try do
      case module.validate(directive) do
        {:ok, %{__struct__: ^module} = validated} ->
          {:ok, validated}

        {:ok, %{__struct__: actual}} ->
          {:error,
           Jido.Error.validation_error("Agent Directive validation changed its type",
             details: %{expected: module, actual: actual}
           )}

        {:error, [%{code: _, path: _, message: _} | _] = issues} ->
          invalid_schema(issues)

        {:error, _reason} = error ->
          error

        result ->
          {:error,
           Jido.Error.validation_error("Agent Directive validate/1 returned an invalid result",
             details: %{directive: module, result: result}
           )}
      end
    rescue
      error ->
        {:error,
         Jido.Error.execution_error("Agent Directive validation failed",
           details: %{directive: module, error: error}
         )}
    catch
      kind, reason ->
        {:error,
         Jido.Error.execution_error("Agent Directive validation failed",
           details: %{directive: module, kind: kind, reason: reason}
         )}
    end
  end

  @doc """
  Creates an emission request. It does not dispatch a Signal.

  The type/data form uses the owning Agent's explicit Signal source when the
  command runs. The full-Signal form preserves its envelope.
  """
  @spec emit(Signal.t() | String.t(), term()) :: Emit.t() | map() | {:error, term()}
  def emit(signal_or_type, dispatch_or_data \\ nil)

  def emit(type, data) when is_binary(type) do
    with :ok <- Jido.Agent.Schema.exact(type),
         :ok <- Jido.Agent.Schema.plain_map(data),
         do: %{kind: :emit, type: type, data: data}
  end

  def emit(%Signal{} = signal, dispatch), do: %Emit{signal: signal, dispatch: dispatch}

  @doc "Creates one correlated response request. It does not dispatch the Signal."
  @spec reply(Signal.t()) :: Reply.t()
  def reply(%Signal{} = signal), do: %Reply{signal: signal}

  @doc false
  def directives(definition, directives) do
    Schema.list(directives, fn
      %{kind: :emit} = request ->
        with {:ok, request} <- emission(request, definition),
             {:ok, signal} <- envelope(request, definition) do
          {:ok, emit(signal)}
        end

      directive ->
        {:ok, directive}
    end)
  end

  defp envelope(%{signal: signal}, _definition), do: {:ok, signal}

  defp envelope(%{type: type, data: data}, definition),
    do: Signal.new(type, data, source: definition.signal_source)

  defp emission(%{kind: :emit, signal: %Signal{} = signal} = request, _definition) do
    with {:ok, _} <- Schema.fields(request, [:kind, :signal]),
         :ok <- emission_signal(signal),
         do: {:ok, request}
  end

  defp emission(%{kind: :emit, type: type, data: data} = request, definition) do
    with {:ok, _} <- Schema.fields(request, [:kind, :type, :data]),
         :ok <- Schema.exact(type),
         :ok <- Schema.plain_map(data),
         :ok <- Schema.static(data),
         :ok <- Error.prefix_result_path(Schema.nonempty(definition.signal_source), :signal_source),
         do: {:ok, request}
  end

  defp emission(_request, _definition),
    do: Error.validation_result(:invalid_directive, [], "Expected a registered emission directive")

  defp emission_signal(signal) do
    case Jido.Joi.validate(Signal.schema(), signal) do
      :ok ->
        Schema.static(signal)

      {:error, issues} ->
        Error.validation_result(:invalid_signal, [], "Invalid Signal envelope", %{issues: issues})
    end
  end

  defp validate_reply_causation(%Reply{signal: signal} = directive) do
    case Signal.get_context(signal, "jidocausationid") do
      value when is_binary(value) and value != "" ->
        :ok

      _value ->
        {:error,
         Jido.Error.validation_error("Agent Reply Directive requires Signal causation",
           details: %{directive: directive}
         )}
    end
  end

  defp validate_reply_causation(_directive), do: :ok
end

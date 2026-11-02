defmodule Jido.AI.Context do
  @moduledoc """
  The lifecycle boundary for one ReqLLM call.

  The request contains the exact `ReqLLM.Context` and options that ReqLLM
  receives. Domain modules can transform the open ReqLLM context. This module
  does not know about threads, memory, skills, tools, or reasoning graphs.
  """

  alias Jido.AI.Context.Snapshot

  @request_schema Zoi.map(
                    %{
                      model: Zoi.any() |> Zoi.nullable() |> Zoi.default(nil),
                      context: Zoi.any(),
                      options: Zoi.list(Zoi.any()) |> Zoi.default([])
                    },
                    unrecognized_keys: :error
                  )

  @schema Zoi.struct(
            __MODULE__,
            %{
              version: Zoi.integer() |> Zoi.default(1),
              id: Zoi.string() |> Zoi.min(1),
              stage: Zoi.enum([:open, :prepared, :completed]) |> Zoi.default(:open),
              request: @request_schema,
              result: Zoi.any() |> Zoi.default(nil),
              metadata: Zoi.map() |> Zoi.default(%{}),
              operations: Zoi.map() |> Zoi.default(%{}),
              digest: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              created_at_ms: Zoi.integer(),
              prepared_at_ms: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil),
              completed_at_ms: Zoi.integer() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true,
            unrecognized_keys: :error
          )

  @type request :: %{
          model: ReqLLM.generation_model_input() | nil,
          context: ReqLLM.Context.t(),
          options: keyword()
        }

  @type result :: nil | {:ok, ReqLLM.Response.t()} | {:error, term()}
  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for a model-call context."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Builds an open lifecycle around an existing ReqLLM context."
  @spec new(ReqLLM.Context.t(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(req_llm_context, opts \\ [])

  def new(%ReqLLM.Context{} = req_llm_context, opts) do
    opts = options_map(opts)

    context = %__MODULE__{
      version: 1,
      id: field(opts, :id) || "context_#{Jido.generate_id()}",
      stage: :open,
      request: %{model: nil, context: req_llm_context, options: []},
      result: nil,
      metadata: field(opts, :metadata) || %{},
      operations: %{},
      digest: nil,
      created_at_ms: System.system_time(:millisecond),
      prepared_at_ms: nil,
      completed_at_ms: nil
    }

    validate(context)
  end

  def new(_req_llm_context, _opts), do: {:error, :invalid_req_llm_context}

  @doc "Validates the lifecycle and its ReqLLM context."
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = context) do
    with {:ok, parsed} <- Zoi.parse(@schema, context),
         true <- Keyword.keyword?(parsed.request.options),
         {:ok, _req_llm_context} <- validate_req_llm_context(parsed.request.context) do
      {:ok, parsed}
    else
      false -> {:error, :invalid_req_llm_options}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_context}
    end
  end

  def validate(_context), do: {:error, :invalid_context}

  @doc "Applies one idempotent transformation to the open ReqLLM context."
  @spec transform(t(), String.t(), (ReqLLM.Context.t() -> ReqLLM.Context.t() | {:ok, ReqLLM.Context.t()})) ::
          {:ok, t()} | {:error, term()}
  def transform(%__MODULE__{} = context, operation_id, fun)
      when is_binary(operation_id) and operation_id != "" and is_function(fun, 1) do
    case Map.fetch(context.operations, operation_id) do
      {:ok, _operation} ->
        {:ok, context}

      :error when context.stage != :open ->
        {:error, :context_not_open}

      :error ->
        apply_transform(context, operation_id, fun)
    end
  end

  def transform(%__MODULE__{}, _operation_id, _fun),
    do: {:error, :context_operation_id_required}

  @doc "Freezes the exact ReqLLM model, context, and options for one call."
  @spec prepare(t(), keyword()) :: {:ok, t()} | {:error, term()}
  def prepare(%__MODULE__{stage: :completed}, _opts), do: {:error, :context_already_completed}

  def prepare(%__MODULE__{stage: :prepared} = context, opts) do
    with {:ok, request} <- prepared_request(context, opts) do
      if request == context.request,
        do: {:ok, context},
        else: {:error, :context_already_prepared}
    end
  end

  def prepare(%__MODULE__{stage: :open} = context, opts) do
    with {:ok, request} <- prepared_request(context, opts) do
      prepared_at = System.system_time(:millisecond)
      digest = request |> Snapshot.request_identity() |> term_digest()

      validate(%{
        context
        | stage: :prepared,
          request: request,
          digest: digest,
          prepared_at_ms: prepared_at
      })
    end
  end

  @doc "Attaches the exact ReqLLM result without changing the request."
  @spec complete(t(), result(), keyword() | map()) :: {:ok, t()} | {:error, term()}
  def complete(context, result, opts \\ [])

  def complete(
        %__MODULE__{stage: :prepared} = context,
        {:ok, %ReqLLM.Response{}} = result,
        opts
      ) do
    finish(context, result, opts)
  end

  def complete(%__MODULE__{stage: :prepared} = context, {:error, _reason} = result, opts) do
    finish(context, result, opts)
  end

  def complete(%__MODULE__{stage: :completed, result: result} = context, result, _opts),
    do: {:ok, context}

  def complete(%__MODULE__{stage: :completed}, _result, _opts),
    do: {:error, :context_already_completed}

  def complete(%__MODULE__{stage: :open}, _result, _opts), do: {:error, :context_not_prepared}
  def complete(%__MODULE__{}, _result, _opts), do: {:error, :invalid_req_llm_result}

  @doc "Captures a portable view before or after a model call."
  @spec snapshot(t(), keyword()) :: Snapshot.t()
  def snapshot(%__MODULE__{} = context, opts \\ []), do: Snapshot.new(context, opts)

  @doc "Compares two context snapshots."
  @spec diff(Snapshot.t(), Snapshot.t()) :: map()
  def diff(%Snapshot{} = before, %Snapshot{} = later), do: Snapshot.diff(before, later)

  @doc false
  @spec identity_document(t()) :: map()
  def identity_document(%__MODULE__{} = context) do
    context
    |> snapshot(content: :none)
    |> Snapshot.to_map()
    |> Map.delete(:captured_at_ms)
  end

  @doc false
  @spec term_digest(term()) :: String.t()
  def term_digest(value) do
    value
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp apply_transform(context, operation_id, fun) do
    before_digest = context.request.context |> Snapshot.req_llm_identity() |> term_digest()

    with {:ok, transformed} <- transformed_context(fun, context.request.context),
         {:ok, transformed} <- ReqLLM.Context.validate(transformed) do
      after_digest = transformed |> Snapshot.req_llm_identity() |> term_digest()

      operation = %{
        before_digest: before_digest,
        after_digest: after_digest
      }

      context
      |> Map.put(:request, %{context.request | context: transformed})
      |> Map.put(:operations, Map.put(context.operations, operation_id, operation))
      |> validate()
    end
  rescue
    error -> {:error, {:context_transform_failed, error}}
  end

  defp transformed_context(fun, req_llm_context) do
    case fun.(req_llm_context) do
      %ReqLLM.Context{} = transformed -> {:ok, transformed}
      {:ok, %ReqLLM.Context{} = transformed} -> {:ok, transformed}
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_req_llm_context}
    end
  end

  defp prepared_request(context, opts) when is_list(opts) do
    model = Keyword.get(opts, :model)
    options = Keyword.get(opts, :options, [])

    cond do
      is_nil(model) -> {:error, :model_required}
      not Keyword.keyword?(options) -> {:error, :invalid_req_llm_options}
      true -> {:ok, %{model: model, context: context.request.context, options: options}}
    end
  end

  defp prepared_request(_context, _opts), do: {:error, :invalid_context_request}

  defp finish(context, result, opts) do
    completion =
      opts
      |> options_map()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    metadata =
      if map_size(completion) == 0 do
        context.metadata
      else
        Map.update(context.metadata, :completion, completion, &Map.merge(&1, completion))
      end

    validate(%{
      context
      | stage: :completed,
        result: result,
        metadata: metadata,
        completed_at_ms: System.system_time(:millisecond)
    })
  end

  defp validate_req_llm_context(%ReqLLM.Context{} = context) do
    with {:ok, context} <- ReqLLM.Context.validate(context),
         :ok <- validate_messages(context.messages) do
      {:ok, context}
    end
  end

  defp validate_req_llm_context(_context), do: {:error, :invalid_req_llm_context}

  defp validate_messages(messages) do
    Enum.reduce_while(messages, :ok, fn message, :ok ->
      with {:ok, _message} <- Zoi.parse(ReqLLM.Message.schema(), message),
           :ok <- validate_content_parts(message.content) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_content_parts(parts) do
    Enum.reduce_while(parts, :ok, fn part, :ok ->
      case Zoi.parse(ReqLLM.Message.ContentPart.schema(), part) do
        {:ok, _part} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp options_map(opts) when is_list(opts), do: Map.new(opts)
  defp options_map(opts) when is_map(opts), do: opts
  defp options_map(_opts), do: %{}

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end

defimpl Runic.Identity.Projectable, for: Jido.AI.Context do
  def identity_document(context), do: Jido.AI.Context.identity_document(context)
end

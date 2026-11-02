defmodule Jido.AI.Thread.Projection do
  @moduledoc """
  Projects the canonical `Jido.Session` Thread into portable model messages.

  Only eligible `:ai_message` entries enter the model context. Runtime
  observations, review records, and request outcomes stay in the Thread but
  outside prompts. Messages from failed or blocked requests stay available for
  inspection but do not enter later model requests. Incomplete tool exchanges
  are also excluded.
  """

  alias Jido.{Session, Thread}

  @roles [:system, :user, :assistant, :tool]

  @doc "Returns the canonical Agent-state schema for a nullable Session."
  @spec schema() :: Zoi.schema()
  def schema, do: Session.state_schema() |> Zoi.nullable() |> Zoi.default(nil)

  @doc "Appends one portable model message to a Session."
  @spec append(Session.t(), ReqLLM.Message.t() | map(), map(), integer()) ::
          {:ok, Session.t()} | {:error, term()}
  def append(%Session{} = session, message, refs \\ %{}, at \\ System.system_time(:millisecond)) do
    with {:ok, payload} <- encode_message(message) do
      entry = Thread.Entry.new(kind: :ai_message, payload: payload, refs: refs, at: at)
      {:ok, Session.append(session, entry)}
    end
  rescue
    _error -> {:error, :invalid_context}
  end

  @doc "Appends one non-message observation to a Session."
  @spec observe(Session.t(), atom(), map(), map(), integer()) :: Session.t()
  def observe(%Session{} = session, kind, payload, refs \\ %{}, at \\ System.system_time(:millisecond))
      when is_atom(kind) and is_map(payload) and is_map(refs) and is_integer(at) do
    Session.append(session, Thread.Entry.new(kind: kind, payload: json(payload), refs: refs, at: at))
  end

  @doc "Projects complete model exchanges from a Session."
  @spec messages(Session.t()) :: {:ok, [map()]} | {:error, :invalid_context}
  def messages(%Session{} = session) do
    with {:ok, projection} <- project(session, %{}) do
      {:ok, projection.messages}
    end
  end

  @doc "Projects a Session into the canonical ReqLLM context and its decisions."
  @spec context(Session.t(), map()) :: {:ok, map()} | {:error, :invalid_context}
  def context(session, config \\ %{})

  def context(%Session{} = session, config) when is_map(config) do
    with {:ok, explanation} <- explain(session, config),
         {:ok, messages} <- req_llm_messages(explanation.entries),
         req_llm_context = ReqLLM.Context.new(messages),
         {:ok, req_llm_context} <- ReqLLM.Context.validate(req_llm_context) do
      {:ok, Map.put(explanation, :context, req_llm_context)}
    else
      _other -> {:error, :invalid_context}
    end
  end

  def context(_session, _config), do: {:error, :invalid_context}

  @doc "Projects a bounded set of complete conversation turns from a Session."
  @spec project(Session.t(), map()) :: {:ok, map()} | {:error, :invalid_context}
  def project(%Session{} = session, config) when is_map(config) do
    with {:ok, explanation} <- explain(session, config) do
      {:ok,
       Map.take(explanation, [
         :messages,
         :available_messages,
         :included_messages,
         :dropped_messages,
         :first_seq,
         :last_seq
       ])}
    end
  end

  def project(_session, _config), do: {:error, :invalid_context}

  @doc "Projects a Thread and reports why each model message was included or excluded."
  @spec explain(Session.t(), map()) :: {:ok, map()} | {:error, :invalid_context}
  def explain(%Session{thread: thread}, config) when is_map(config) do
    with {:ok, _thread} <- Thread.validate(thread) do
      outcomes = request_outcomes(thread.entries)
      message_entries = Enum.filter(thread.entries, &message_entry?/1)
      eligible_entries = Enum.filter(message_entries, &context_entry?(&1, outcomes))

      eligible_entries
      |> Enum.reduce_while({:ok, []}, fn entry, {:ok, messages} ->
        case decode_message(entry.payload) do
          {:ok, message} -> {:cont, {:ok, [{entry, message} | messages]}}
          {:error, _reason} -> {:halt, {:error, :invalid_context}}
        end
      end)
      |> case do
        {:ok, pairs} ->
          completed = pairs |> Enum.reverse() |> complete_exchanges()
          selected = select_turns(completed, config)
          completed_ids = entry_ids(completed)
          selected_ids = entry_ids(selected)

          {:ok,
           %{
             messages: Enum.map(selected, &elem(&1, 1)),
             entries: Enum.map(selected, &portable_pair/1),
             decisions:
               projection_decisions(
                 message_entries,
                 eligible_entries,
                 completed_ids,
                 selected_ids,
                 outcomes
               ),
             available_messages: length(completed),
             included_messages: length(selected),
             dropped_messages: length(completed) - length(selected),
             first_seq: sequence(List.first(selected)),
             last_seq: sequence(List.last(selected))
           }}

        error ->
          error
      end
    else
      _other -> {:error, :invalid_context}
    end
  end

  def explain(_session, _config), do: {:error, :invalid_context}

  @doc "Returns the final included Thread sequence for one projection."
  @spec breakpoint(Session.t()) :: non_neg_integer() | nil
  def breakpoint(%Session{thread: thread}) do
    thread.entries
    |> context_entries()
    |> complete_exchange_entries()
    |> List.last()
    |> case do
      nil -> nil
      entry -> entry.seq
    end
  end

  defp complete_exchange_entries(entries) do
    entries
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, pairs} ->
      case decode_message(entry.payload) do
        {:ok, message} -> {:cont, {:ok, [{entry, message} | pairs]}}
        {:error, _reason} -> {:halt, {:error, :invalid_context}}
      end
    end)
    |> case do
      {:ok, pairs} -> pairs |> Enum.reverse() |> complete_exchanges() |> Enum.map(&elem(&1, 0))
      {:error, _reason} -> []
    end
  end

  defp context_entries(entries) do
    outcomes = request_outcomes(entries)

    Enum.filter(entries, fn entry ->
      message_entry?(entry) and context_entry?(entry, outcomes)
    end)
  end

  defp message_entry?(entry), do: entry.kind in [:ai_message, "ai_message"]

  defp entry_ids(pairs), do: MapSet.new(pairs, fn {entry, _message} -> entry.id end)

  defp portable_pair({entry, message}) do
    %{
      id: entry.id,
      seq: entry.seq,
      at: entry.at,
      refs: entry.refs,
      message: message
    }
  end

  defp projection_decisions(entries, eligible, completed_ids, selected_ids, outcomes) do
    eligible_ids = MapSet.new(eligible, & &1.id)

    Enum.map(entries, fn entry ->
      cond do
        not MapSet.member?(eligible_ids, entry.id) ->
          decision(entry, :excluded, request_outcome_reason(entry, outcomes))

        not MapSet.member?(completed_ids, entry.id) ->
          decision(entry, :excluded, :incomplete_tool_exchange)

        not MapSet.member?(selected_ids, entry.id) ->
          decision(entry, :excluded, :outside_context_window)

        true ->
          decision(entry, :included, :projected)
      end
    end)
  end

  defp decision(entry, state, reason) do
    %{entry_id: entry.id, seq: entry.seq, state: state, reason: reason, refs: entry.refs}
  end

  defp request_outcome_reason(entry, outcomes) do
    case field(entry.refs, :run_id) do
      run_id when is_binary(run_id) and run_id != "" ->
        if Map.get(outcomes, run_id) == false, do: :request_not_completed, else: :not_eligible

      _other ->
        :not_eligible
    end
  end

  defp request_outcomes(entries) do
    Enum.reduce(entries, %{}, fn entry, outcomes ->
      if entry.kind in [:ai_request_outcome, "ai_request_outcome"] do
        case field(entry.refs, :run_id) do
          run_id when is_binary(run_id) and run_id != "" ->
            Map.put(outcomes, run_id, field(entry.payload, :status) in [:completed, "completed"])

          _other ->
            outcomes
        end
      else
        outcomes
      end
    end)
  end

  defp context_entry?(entry, outcomes) do
    case field(entry.refs, :run_id) do
      run_id when is_binary(run_id) and run_id != "" -> Map.get(outcomes, run_id, true)
      _other -> true
    end
  end

  # Keep an assistant tool request only when every call has one matching tool result.
  defp complete_exchanges(pairs) do
    {completed, _pending, _open} =
      Enum.reduce(pairs, {[], [], %{}}, fn {entry, message} = pair, {completed, pending, open} ->
        cond do
          message.role == :assistant and message.tool_calls != [] ->
            ids = Enum.map(message.tool_calls, & &1.id)

            if ids == Enum.uniq(ids) and Enum.all?(ids, &(is_binary(&1) and &1 != "")) do
              {completed, [pair], Map.new(message.tool_calls, &{&1.id, &1.name})}
            else
              {completed, [], %{}}
            end

          message.role == :tool and Map.has_key?(open, message.tool_call_id) and
              message.name in [nil, open[message.tool_call_id]] ->
            next_open = Map.delete(open, message.tool_call_id)
            next_pending = pending ++ [{entry, message}]

            if map_size(next_open) == 0,
              do: {completed ++ next_pending, [], next_open},
              else: {completed, next_pending, next_open}

          message.role == :tool ->
            {completed, pending, open}

          true ->
            {completed ++ [pair], [], %{}}
        end
      end)

    completed
  end

  defp select_turns(pairs, config) do
    limits = %{
      max_messages: positive_limit(field(config, :max_messages)),
      max_bytes: positive_limit(field(config, :max_bytes))
    }

    pairs
    |> conversation_turns()
    |> Enum.reverse()
    |> Enum.reduce_while({[], 0, 0}, fn turn, {selected, messages, bytes} ->
      next_messages = messages + length(turn)
      next_bytes = bytes + turn_bytes(turn)

      if selected != [] and exceeds?(next_messages, next_bytes, limits) do
        {:halt, {selected, messages, bytes}}
      else
        {:cont, {[turn | selected], next_messages, next_bytes}}
      end
    end)
    |> elem(0)
    |> Enum.concat()
  end

  defp conversation_turns(pairs) do
    {turns, current} =
      Enum.reduce(pairs, {[], []}, fn {_entry, message} = pair, {turns, current} ->
        if message.role == :user and current != [] do
          {[Enum.reverse(current) | turns], [pair]}
        else
          {turns, [pair | current]}
        end
      end)

    case current do
      [] -> Enum.reverse(turns)
      values -> Enum.reverse([Enum.reverse(values) | turns])
    end
  end

  defp exceeds?(messages, bytes, limits) do
    over?(messages, limits.max_messages) or over?(bytes, limits.max_bytes)
  end

  defp over?(_value, nil), do: false
  defp over?(value, limit), do: value > limit
  defp positive_limit(value) when is_integer(value) and value > 0, do: value
  defp positive_limit(_value), do: nil
  defp turn_bytes(turn), do: turn |> Enum.map(&elem(&1, 1)) |> Jason.encode!() |> byte_size()
  defp sequence(nil), do: nil
  defp sequence({entry, _message}), do: entry.seq

  defp encode_message(%ReqLLM.Message{} = message) do
    encode_message(%{
      role: message.role,
      content: portable_content(message.content),
      name: message.name,
      tool_call_id: message.tool_call_id,
      tool_calls: message.tool_calls || [],
      metadata: message.metadata,
      reasoning_details: message.reasoning_details
    })
  end

  defp encode_message(message) when is_map(message) do
    with role when role in @roles <- role(field(message, :role)),
         content when is_binary(content) or is_list(content) <- field(message, :content) || "",
         {:ok, tool_calls} <- encode_tool_calls(field(message, :tool_calls) || []) do
      {:ok,
       json(%{
         "version" => 1,
         "role" => Atom.to_string(role),
         "content" => content,
         "name" => field(message, :name),
         "tool_call_id" => field(message, :tool_call_id),
         "tool_calls" => tool_calls,
         "output" => field(message, :output),
         "metadata" => field(message, :metadata) || %{},
         "reasoning_details" => field(message, :reasoning_details)
       })}
    else
      _other -> {:error, :invalid_message}
    end
  rescue
    _error -> {:error, :invalid_message}
  end

  defp decode_message(%{"version" => 1} = payload) do
    with role when role in @roles <- role(payload["role"]),
         content when is_binary(content) or is_list(content) <- payload["content"] || "",
         {:ok, tool_calls} <- decode_tool_calls(payload["tool_calls"] || []) do
      {:ok,
       %{
         role: role,
         content: content,
         name: payload["name"],
         tool_call_id: payload["tool_call_id"],
         tool_calls: tool_calls,
         output: payload["output"],
         metadata: payload["metadata"] || %{},
         reasoning_details: payload["reasoning_details"]
       }}
    else
      _other -> {:error, :invalid_message}
    end
  end

  defp decode_message(_payload), do: {:error, :invalid_message}

  defp encode_tool_calls(calls) when is_list(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, fn call, {:ok, encoded} ->
      case tool_call(call) do
        {:ok, value} -> {:cont, {:ok, [value | encoded]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end
  end

  defp encode_tool_calls(_calls), do: {:error, :invalid_message}

  defp decode_tool_calls(calls), do: encode_tool_calls(calls)

  defp tool_call(%ReqLLM.ToolCall{} = call) do
    normalized = ReqLLM.ToolCall.to_map(call)
    metadata = ReqLLM.ToolCall.metadata(call)
    metadata = if ReqLLM.ToolCall.builtin?(call), do: Map.put(metadata, :builtin?, true), else: metadata

    if map_size(metadata) > 0,
      do: {:ok, Map.put(normalized, :metadata, json(metadata))},
      else: {:ok, normalized}
  end

  defp tool_call(call) when is_map(call) do
    id = field(call, :id)
    name = field(call, :name)
    arguments = field(call, :arguments)

    if is_binary(id) and id != "" and is_binary(name) and name != "" and is_map(arguments) do
      normalized = %{id: id, name: name, arguments: json(arguments)}
      metadata = field(call, :metadata)

      if is_map(metadata) and map_size(metadata) > 0,
        do: {:ok, Map.put(normalized, :metadata, json(metadata))},
        else: {:ok, normalized}
    else
      {:error, :invalid_message}
    end
  end

  defp tool_call(_call), do: {:error, :invalid_message}

  defp role(value) when value in @roles, do: value
  defp role("system"), do: :system
  defp role("user"), do: :user
  defp role("assistant"), do: :assistant
  defp role("tool"), do: :tool
  defp role(_value), do: nil

  defp req_llm_messages(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, messages} ->
      with {:ok, message} <- req_llm_message(entry.message) do
        {:cont, {:ok, [put_thread_source(message, entry) | messages]}}
      else
        _error -> {:halt, {:error, :invalid_context}}
      end
    end)
    |> case do
      {:ok, messages} -> {:ok, Enum.reverse(messages)}
      error -> error
    end
  end

  defp req_llm_message(%{role: :tool, tool_call_id: id} = message)
       when is_binary(id) and id != "" do
    output = tool_result_input(message)

    {:ok,
     ReqLLM.Context.tool_result_message(
       message.name,
       id,
       output,
       message.metadata || %{}
     )}
  rescue
    _error -> {:error, :invalid_context}
  end

  defp req_llm_message(%{role: :assistant, tool_calls: calls} = message)
       when is_list(calls) and calls != [] do
    with {:ok, %ReqLLM.Context{messages: [assistant]}} <- ReqLLM.Context.normalize(message),
         {:ok, tool_calls} <- req_llm_tool_calls(calls) do
      {:ok, %{assistant | tool_calls: tool_calls}}
    else
      _other -> {:error, :invalid_context}
    end
  rescue
    _error -> {:error, :invalid_context}
  end

  defp req_llm_message(message) do
    case ReqLLM.Context.normalize(message) do
      {:ok, %ReqLLM.Context{messages: [message]}} -> {:ok, message}
      _other -> {:error, :invalid_context}
    end
  rescue
    _error -> {:error, :invalid_context}
  end

  defp tool_result_input(%{content: content} = message) when is_list(content) and content != [] do
    metadata = message.metadata || %{}
    result_metadata = field(metadata, :tool_result_metadata) || %{}

    %ReqLLM.ToolResult{
      content: normalize_content_parts(content),
      output: message.output,
      metadata: result_metadata
    }
  end

  defp tool_result_input(message), do: message.output || message.content

  defp normalize_content_parts(content) do
    case ReqLLM.Context.normalize(%{role: :user, content: content}) do
      {:ok, %ReqLLM.Context{messages: [%ReqLLM.Message{content: parts}]}} -> parts
      _other -> raise ArgumentError, "invalid tool result content"
    end
  end

  defp req_llm_tool_calls(calls) do
    Enum.reduce_while(calls, {:ok, []}, fn call, {:ok, normalized} ->
      case req_llm_tool_call(call) do
        {:ok, tool_call} -> {:cont, {:ok, [tool_call | normalized]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp req_llm_tool_call(call) do
    id = field(call, :id)
    name = field(call, :name)
    arguments = field(call, :arguments)
    metadata = field(call, :metadata) || %{}
    encoded = if is_binary(arguments), do: arguments, else: Jason.encode!(arguments)

    tool_call =
      if field(metadata, :builtin?) == true,
        do: ReqLLM.ToolCall.new_builtin(id, name, encoded),
        else: ReqLLM.ToolCall.new(id, name, encoded)

    {:ok, ReqLLM.ToolCall.put_metadata(tool_call, Map.delete(metadata, :builtin?))}
  rescue
    _error -> {:error, :invalid_context}
  end

  defp put_thread_source(message, entry) do
    metadata = message.metadata || %{}
    jido = field(metadata, :jido) || %{}

    source = %{
      type: :thread_entry,
      entry_id: entry.id,
      seq: entry.seq,
      at: entry.at,
      refs: entry.refs
    }

    %{message | metadata: Map.put(metadata, :jido, Map.put(jido, :source, source))}
  end

  defp portable_content([%ReqLLM.Message.ContentPart{type: :text, text: text}])
       when is_binary(text),
       do: text

  defp portable_content(content), do: content

  defp field(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()
end

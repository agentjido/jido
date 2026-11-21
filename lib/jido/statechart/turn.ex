defmodule Jido.Statechart.Turn do
  @moduledoc false

  use Jido.Flow, name: "statechart_turn"

  alias Jido.Statechart.SCXML

  defmodule Advance do
    @moduledoc false
    use Jido.Action, name: "statechart_advance"
    alias Jido.Statechart.BasicHTTP
    alias Jido.Statechart.Configuration
    alias Jido.Statechart.SCXML
    alias Jido.Statechart.SCXML.Reference

    @scxml_types [nil, "scxml", SCXML.event_processor()]
    @invoke_types SCXML.invoke_types()
    @http_type BasicHTTP.type()

    @impl true
    def run(%{cancel: true} = work, _context), do: complete(work, nil, :cancelled)

    def run(%{finalize: [_ | _] = blocks} = work, context) do
      with {:ok, work} <- execute_blocks(blocks, %{work | finalize: []}), do: run(work, context)
    end

    def run(%{session: %{configuration: []}} = work, _context) do
      work = initialize_data(work)
      enter(work, work.chart.initial)
    end

    def run(%{session: session, chart: chart} = work, _context) do
      case Configuration.select(chart, session, work, &enabled/2) do
        {[], work} -> next_event(work)
        {transitions, work} -> microstep(work, transitions)
      end
    end

    defp initialize_data(%{chart: %{binding: :late} = chart} = work) do
      {root, nested} = Enum.split(chart.data, length(chart.root_data_keys))

      data =
        Enum.reduce(nested, work.session.data, fn {key, _expr}, data ->
          Map.put_new(data, key, nil)
        end)

      initialize_data(root, put_in(work.session.data, data))
    end

    defp initialize_data(work), do: initialize_data(work.chart.data, work)

    defp initialize_data(declarations, work) do
      Enum.reduce(declarations, work, fn {key, expression}, work ->
        if Map.has_key?(work.session.data, key), do: work, else: bind_data(key, expression, work)
      end)
    end

    defp bind_data(key, expression, work) do
      case evaluate(expression, work) do
        {:ok, value} ->
          put_in(work.session.data[key], value)

        {:error, _reason} ->
          work |> put_in([:session, :data, key], nil) |> enqueue("error.execution", %{})
      end
    end

    defp next_event(%{event: event} = work) when not is_nil(event),
      do: {:ok, %{work | event: nil}}

    defp next_event(work) do
      case :queue.out(work.internal) do
        {{:value, event}, internal} ->
          session = %{work.session | event: event}
          {:ok, %{work | event: event, session: session, internal: internal}}

        {:empty, _internal} ->
          work = prepare_invokes(work)
          {:ok, %{work | pending: not :queue.is_empty(work.internal)}}
      end
    end

    defp prepare_invokes(work) do
      states = Enum.filter(work.session.configuration, &MapSet.member?(work.entered, &1))

      Enum.reduce(states, %{work | entered: MapSet.new()}, fn state, work ->
        Enum.reduce(List.wrap(work.chart.states[state].invoke), work, fn invoke, work ->
          prepare_invoke(state, invoke, work)
        end)
      end)
    end

    defp prepare_invoke(state, invoke, work) do
      with {:ok, type} when type in @invoke_types <- send_value(Map.get(invoke, :type), work),
           {:ok, source} <- invoke_source(invoke.source, work),
           {:ok, params} <- send_payload({:params, Map.get(invoke, :params, [])}, work),
           {:ok, invocation, work} <- prepare_invoke_id(invoke, state, work) do
        prepared = %{
          invocation: invocation,
          source: source,
          data: SCXML.param_data(params) || %{}
        }

        update_in(
          work.ready_invokes,
          &Map.update(&1, state, [prepared], fn list -> [prepared | list] end)
        )
      else
        _error -> enqueue(work, "error.execution", %{})
      end
    end

    defp invoke_source({:inline, chart}, _work), do: {:ok, chart}

    defp invoke_source({:expression, expr}, work) do
      case evaluate(expr, work) do
        {:ok, {:inline, chart}} -> {:ok, chart}
        _error -> :error
      end
    end

    defp invoke_source({:registered, expr}, work) do
      with {:ok, src} when is_binary(src) and src != "" <- send_value(expr, work) do
        Map.fetch(Map.get(work.registry, :invokes, %{}), src)
      end
    end

    defp prepare_invoke_id(invoke, state, work) do
      child = "statechart-" <> Jido.Id.uuid7()
      id = invoke.id || state <> "." <> child

      invocation = %{
        id: id,
        child: child,
        forward: invoke.forward,
        finalize: Map.get(invoke, :finalize, [])
      }

      case Map.get(invoke, :idlocation) do
        nil ->
          {:ok, invocation, work}

        key ->
          with {:ok, work} <- write_data(key, id, work), do: {:ok, invocation, work}
      end
    end

    defp microstep(work, transitions) do
      targets = Enum.flat_map(transitions, & &1.targets)
      exits = MapSet.new(Enum.flat_map(transitions, & &1.exits))
      blocks = transitions |> Enum.sort_by(& &1.order) |> Enum.map(& &1.actions)

      with {:ok, work} <- exit(work, exits),
           {:ok, work} <- execute_blocks(blocks, work) do
        enter(%{work | event: nil}, targets)
      end
    end

    defp exit(work, exits) do
      work = put_in(work.session.history, Configuration.remember(work.chart, work.session, exits))

      ids =
        work.session.configuration |> Enum.reverse() |> Enum.filter(&MapSet.member?(exits, &1))

      reduce_work(ids, work, fn id, work ->
        with {:ok, work} <- execute_blocks(work.chart.states[id].onexit, work) do
          session = work.session

          session = %{
            session
            | configuration: List.delete(session.configuration, id),
              invocations: Map.delete(session.invocations, id)
          }

          {:ok,
           %{
             work
             | session: session,
               entered: MapSet.delete(work.entered, id),
               ready_invokes: Map.delete(work.ready_invokes, id)
           }}
        end
      end)
    end

    defp enter(work, targets) do
      with {:ok, plan} <- Configuration.plan(work.chart, work.session, targets),
           {:ok, work} <- reduce_work(plan, work, &enter_state/2) do
        configuration = Enum.map(plan, &elem(&1, 0))
        state = Enum.find(configuration, &Configuration.atomic?(work.chart, &1))
        work = %{work | session: %{work.session | configuration: configuration, state: state}}

        case work.chart.states[state] do
          %{kind: :final, parent: nil, completion: completion} ->
            complete(work, completion)

          _ ->
            {:ok, work}
        end
      end
    end

    defp complete(work, completion, status \\ :completed) do
      with {:ok, work} <- exit(work, MapSet.new(work.session.configuration)) do
        {data, work} = payload(completion, work)
        session = %{work.session | status: status, completion: data}
        {:ok, %{work | session: session, pending: false}}
      end
    end

    defp enter_state({id, blocks}, work) do
      if id in work.session.configuration do
        execute_blocks(blocks, work)
      else
        work = update_in(work.session.configuration, &(&1 ++ [id]))
        work = update_in(work.entered, &MapSet.put(&1, id))
        state = work.chart.states[id]
        work = bind_state(id, Map.get(state, :data, []), work)

        with {:ok, work} <- execute_blocks(state.onentry ++ blocks, work) do
          {:ok, queue_completion(state, work)}
        end
      end
    end

    defp bind_state(id, [_ | _] = declarations, %{chart: %{binding: :late}} = work) do
      bound = Map.get(work.session, :bound_states, [])

      if id in bound do
        work
      else
        work = update_in(work.session, &Map.put(&1, :bound_states, [id | bound]))

        Enum.reduce(declarations, work, fn {key, expression}, work ->
          bind_data(key, expression, work)
        end)
      end
    end

    defp bind_state(_id, _declarations, work), do: work

    defp queue_completion(%{kind: :final, parent: parent, completion: completion}, work)
         when not is_nil(parent) do
      {data, work} = payload(completion, work)

      work
      |> enqueue("done.state." <> parent, data)
      |> queue_parallel_completion(work.chart.states[parent].parent)
    end

    defp queue_completion(_state, work), do: work

    defp payload({:params, params}, work) do
      {pairs, work} =
        Enum.reduce(params, {[], work}, fn {name, expression}, {pairs, work} ->
          case evaluate(expression, work) do
            {:ok, value} -> {[{name, value} | pairs], work}
            {:error, _reason} -> {pairs, enqueue(work, "error.execution", %{})}
          end
        end)

      {pairs |> Enum.reverse() |> SCXML.param_data(), work}
    end

    defp payload({:expression, expression}, work) do
      case evaluate(expression, work) do
        {:ok, value} -> {value, work}
        {:error, _reason} -> {nil, enqueue(work, "error.execution", %{})}
      end
    end

    defp payload(data, work), do: {data, work}

    defp queue_parallel_completion(work, id) do
      with %{kind: :parallel, parent: parent} <- work.chart.states[id],
           true <- Configuration.final?(work.chart, work.session.configuration, id) do
        work
        |> enqueue("done.state." <> id, nil)
        |> queue_parallel_completion(parent)
      else
        _ -> work
      end
    end

    defp enabled(transition, work) do
      if matches?(transition.events, work.event) do
        case guard(transition.guard, work) do
          {:ok, enabled} -> {enabled, work}
          :error -> {false, enqueue(work, "error.execution", %{})}
        end
      else
        {false, work}
      end
    end

    defp matches?(nil, event), do: is_nil(event)
    defp matches?(_events, nil), do: false

    defp matches?(events, %{name: name}) do
      Enum.any?(events, fn descriptor ->
        prefix = String.trim_trailing(descriptor, ".*")
        descriptor == "*" or name == prefix or String.starts_with?(name, prefix <> ".")
      end)
    end

    defp guard(nil, _work), do: {:ok, true}
    defp guard(result, _work) when is_boolean(result), do: {:ok, result}
    defp guard({:in_state, id}, work), do: {:ok, id in work.session.configuration}

    defp guard({:bound, references}, work) do
      {:ok, Enum.all?(List.wrap(references), &match?({:ok, _}, evaluate(&1, work)))}
    end

    defp guard({:prefix, prefix, value}, work) do
      with {:ok, prefix} when is_binary(prefix) <- evaluate(prefix, work),
           {:ok, value} when is_binary(value) <- evaluate(value, work) do
        {:ok, String.starts_with?(value, prefix)}
      else
        _error -> :error
      end
    end

    defp guard(%Jido.Expr.Operation{} = expression, work) do
      case evaluate(expression, work) do
        {:ok, result} when is_boolean(result) -> {:ok, result}
        _ -> :error
      end
    end

    defp guard(id, work) do
      with {module, function} <- get_in(work.registry, [:guards, id]),
           result when is_boolean(result) <-
             apply(module, function, [%{data: work.session.data, event: work.session.event}]) do
        {:ok, result}
      else
        _ -> :error
      end
    rescue
      _error -> :error
    end

    defp execute_blocks(blocks, work), do: reduce_work(blocks, work, &execute_block/2)

    defp execute_block(actions, work) do
      case execute_actions(actions, work) do
        {:event_error, reason, work} -> {:ok, enqueue_error(work, reason)}
        result -> result
      end
    end

    defp execute_actions(actions, work) do
      Enum.reduce_while(actions, {:ok, work}, fn action, {:ok, work} ->
        case execute_action(action, work) do
          {:ok, _work} = next -> {:cont, next}
          {:event_error, name} -> {:halt, {:event_error, name, work}}
          {:event_error, _, _} = error -> {:halt, error}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end

    defp execute_action({:raise, name}, work),
      do: {:ok, enqueue(work, %{name: name, type: "internal", data: %{}})}

    defp execute_action({:copy_returned, bindings}, work) do
      returned = work.session.event.data

      Enum.reduce_while(bindings, {:ok, work}, fn {name, location}, {:ok, work} = result ->
        with %{^name => value} <- returned,
             {:ok, work} <- write_data(location, value, work) do
          {:cont, {:ok, work}}
        else
          :error -> {:halt, {:event_error, "error.execution", work}}
          _missing -> {:cont, result}
        end
      end)
    end

    defp execute_action({:if, branches}, work) do
      Enum.reduce_while(branches, {:ok, work}, fn {condition, actions}, {:ok, work} = result ->
        case guard(condition, work) do
          {:ok, true} -> {:halt, execute_actions(actions, work)}
          {:ok, false} -> {:cont, result}
          :error -> {:cont, {:ok, enqueue(work, "error.execution", %{})}}
        end
      end)
    end

    defp execute_action({:if, condition, actions}, work),
      do: execute_action({:if, [{condition, actions}]}, work)

    defp execute_action({:foreach, expression, item, index, actions}, work) do
      with {:ok, array} when is_list(array) and is_integer(length(array)) <- evaluate(expression, work),
           true <- local_variable?(item) and (is_nil(index) or local_variable?(index)) do
        data = Map.put_new(work.session.data, item, nil)
        data = if index, do: Map.put_new(data, index, nil), else: data
        work = put_in(work.session.data, data)

        array
        |> Enum.with_index()
        |> Enum.reduce_while({:ok, work}, fn {value, offset}, {:ok, work} ->
          work = put_in(work.session.data[item], value)
          work = if index, do: put_in(work.session.data[index], offset), else: work

          case execute_actions(actions, work) do
            {:ok, _work} = next -> {:cont, next}
            error -> {:halt, error}
          end
        end)
      else
        _ -> {:event_error, "error.execution"}
      end
    end

    defp execute_action({:send, send}, work) do
      with {:ok, name} <- send_value(send.event, work),
           {:ok, target} <- send_value(send.target, work),
           {:ok, type} when type in @scxml_types or type == @http_type <-
             send_value(send.type, work),
           true <- (is_binary(name) and name != "") or (is_nil(name) and type == @http_type),
           {:ok, duration} <- send_value(send.delay, work),
           {:ok, delay} <- SCXML.duration(duration),
           {:ok, data} <- send_payload(send.payload, work),
           {:ok, id, work} <- send_id(send, work) do
        message = %{name: name, data: data}
        message = if id, do: Map.put(message, :sendid, id), else: message

        case send_to(type, target, message, delay, work) do
          {:event_error, name} -> send_error(work, name, id)
          result -> result
        end
      else
        _ -> send_error(work, "error.execution", send[:id])
      end
    end

    defp execute_action({:log, label, expression}, work) do
      case evaluate(expression, work) do
        {:ok, value} -> {:ok, %{work | effects: [{:log, label, value} | work.effects]}}
        {:error, _reason} -> {:event_error, "error.execution"}
      end
    end

    defp execute_action({:cancel, expr}, work) do
      case send_value(expr, work) do
        {:ok, id} when is_binary(id) and id != "" ->
          {:ok, %{work | effects: [{:cancel_send, id} | work.effects]}}

        _error ->
          {:event_error, "error.execution"}
      end
    end

    defp execute_action({:assign, key, expression}, work) do
      with {:ok, value} <- evaluate(expression, work),
           {:ok, work} <- write_data(key, value, work) do
        {:ok, work}
      else
        _error -> {:event_error, "error.execution"}
      end
    end

    defp execute_action({:action, id, key}, work) do
      module = binding!(work.registry, :actions, id)
      data = work.session.data
      params = if key, do: Map.fetch!(data, key), else: data

      case Jido.Exec.run(module, params, %{event: work.session.event, data: data}) do
        {:ok, changes} when is_map(changes) ->
          {:ok, %{work | session: %{work.session | data: Map.merge(data, changes)}}}

        {:error, _reason} = error ->
          error

        _ ->
          {:error, :expected_action_data}
      end
    end

    defp send_error(work, name, id) do
      event = %{name: name, type: "platform", data: %{}}
      event = if id, do: Map.put(event, :sendid, id), else: event
      {:event_error, event, work}
    end

    defp enqueue_error(work, %{name: _} = event), do: enqueue(work, event)
    defp enqueue_error(work, name), do: enqueue(work, name, %{})

    defp send_value({:expression, expr}, work) do
      case evaluate(expr, work) do
        {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
        _ -> :error
      end
    end

    defp send_value(value, _work), do: {:ok, value}

    defp send_id(%{idlocation: key}, work) when is_binary(key) do
      id = Jido.Id.uuid7()
      with {:ok, work} <- write_data(key, id, work), do: {:ok, id, work}
    end

    defp send_id(send, work), do: {:ok, Map.get(send, :id), work}

    defp send_payload({:content, body}, _work), do: {:ok, body}

    defp send_payload({:params, params}, work) do
      with {:ok, reversed} <-
             reduce_work(params, [], fn {name, expression}, pairs ->
               with {:ok, value} <- evaluate(expression, work),
                    do: {:ok, [{name, value} | pairs]}
             end) do
        {:ok, Enum.reverse(reversed)}
      end
    end

    defp send_to(
           @http_type,
           target,
           message,
           delay,
           %{session: %{http_location: location}} = work
         )
         when is_binary(location) do
      case {target, URI.new(target || "")} do
        {nil, _} ->
          {:event_error, "error.communication"}

        {_, {:ok, %URI{scheme: scheme, host: host}}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          {:ok, %{work | effects: [{:http_post, target, message, delay} | work.effects]}}

        _ ->
          {:event_error, "error.execution"}
      end
    end

    defp send_to(@http_type, _target, _name, _delay, _work), do: {:event_error, "error.execution"}

    defp send_to(_type, target, %{data: params} = message, delay, work) when is_list(params),
      do: send_to(target, %{message | data: SCXML.param_data(params)}, delay, work)

    defp send_to(_type, target, name, delay, work), do: send_to(target, name, delay, work)

    defp send_to(nil, message, delay, work),
      do: send_event(work, work.session.owner, message, delay)

    defp send_to("#_internal", message, 0, work),
      do: {:ok, enqueue(work, Map.put(message, :type, "internal"))}

    defp send_to("#_parent", message, delay, %{session: %{parent: %{agent: parent}}} = work),
      do: send_event(work, parent, message, delay)

    defp send_to("#_parent", _name, _delay, _work),
      do: {:event_error, "error.communication"}

    defp send_to("#_scxml_" <> id, message, delay, %{session: session} = work)
         when id != "" do
      reachable =
        id == session.owner or
          match?(%{agent: ^id}, session.parent) or
          Enum.any?(active_invocations(session), &(&1.child == id))

      if reachable,
        do: send_event(work, id, message, delay),
        else: {:event_error, "error.communication"}
    end

    defp send_to("#_" <> id, message, delay, work) when id != "" do
      case Enum.find(active_invocations(work.session), &(&1.id == id)) do
        nil -> {:event_error, "error.communication"}
        %{child: child} -> send_event(work, child, message, delay)
      end
    end

    defp send_to(_target, _name, _delay, _work),
      do: {:event_error, "error.execution"}

    defp active_invocations(session),
      do: Enum.flat_map(session.configuration, &List.wrap(session.invocations[&1]))

    defp send_event(
           %{cancel: true, session: %{parent: %{agent: parent}}} = work,
           parent,
           _message,
           _delay
         ),
         do: {:ok, work}

    defp send_event(work, agent, message, delay) do
      message =
        case work.session.parent do
          %{agent: ^agent, id: id} -> Map.put(message, :invokeid, id)
          _parent -> message
        end

      {:ok, %{work | effects: [{:send_event, agent, message, delay} | work.effects]}}
    end

    defp evaluate(%Jido.Expr.Operation{} = expression, work),
      do: Jido.Expr.evaluate(expression, resolve: &resolve_reference(&1, work))

    defp evaluate(%Reference{} = reference, work), do: resolve_reference(reference, work)

    defp evaluate({:append, source, suffix}, work) do
      case evaluate(source, work) do
        {:ok, array} when is_list(array) -> {:ok, array ++ suffix}
        _error -> {:error, :expected_array}
      end
    end

    defp evaluate({:source, source}, work) do
      with {:ok, path} <- Map.fetch(Map.get(work.registry, :data_sources, %{}), source),
           {:ok, content} <- File.read(path) do
        JSON.decode(content)
      else
        :error -> {:error, :unknown_data_source}
        {:error, _reason} = error -> error
      end
    end

    defp evaluate({:invalid_expression, source}, _work),
      do: {:error, {:invalid_expression, source}}

    defp evaluate(value, _work), do: {:ok, value}

    defp resolve_reference(%Reference{scope: :event}, %{session: %{event: nil}}),
      do: {:error, :event_unbound}

    defp resolve_reference(%Reference{scope: :event, key: key}, work) do
      reference_path(work.session.event, List.wrap(key))
    end

    defp resolve_reference(%Reference{scope: :data, key: key}, work),
      do: reference_path(work.session.data, List.wrap(key))

    defp resolve_reference(%Reference{scope: :session, key: key}, work) do
      fetch_path(%{owner: work.session.owner, name: Map.get(work.chart, :name)}, [key])
    end

    defp resolve_reference(%Reference{scope: :ioprocessors, key: key}, work) do
      processors = %{SCXML.event_processor() => %{location: SCXML.location(work.session.owner)}}

      processors =
        case Map.get(work.session, :http_location) do
          nil -> processors
          location -> Map.put(processors, @http_type, %{location: location})
        end

      fetch_path(processors, List.wrap(key))
    end

    defp reference_path(map, [root | [_ | _] = path]) do
      with {:ok, value} <- fetch_path(map, [root]) do
        case fetch_path(value, path) do
          {:ok, _value} = result -> result
          {:error, :unknown_expression_reference} -> {:ok, nil}
        end
      end
    end

    defp reference_path(map, path), do: fetch_path(map, path)

    defp fetch_path(value, []), do: {:ok, value}
    defp fetch_path(map, [key | rest]) when is_map_key(map, key), do: fetch_path(map[key], rest)

    defp fetch_path(map, [key | rest]) when is_map(map) and is_binary(key) do
      fetch_path(map, [String.to_existing_atom(key) | rest])
    rescue
      ArgumentError -> {:error, :unknown_expression_reference}
    end

    defp fetch_path(_value, _path), do: {:error, :unknown_expression_reference}

    defp enqueue(work, name, data),
      do: enqueue(work, %{name: name, type: "platform", data: data})

    defp enqueue(work, event),
      do: %{work | internal: :queue.in(SCXML.event(event), work.internal)}

    defp local_variable?(key), do: SCXML.variable?(key) and not SCXML.reserved?(key)

    defp write_data(key, value, work) do
      if not SCXML.reserved?(key) and Map.has_key?(work.session.data, key),
        do: {:ok, put_in(work.session.data[key], value)},
        else: :error
    end

    defp reduce_work(values, work, fun) do
      Enum.reduce_while(values, {:ok, work}, fn item, {:ok, work} ->
        case fun.(item, work) do
          {:ok, _work} = next -> {:cont, next}
          {:error, _reason} = error -> {:halt, error}
        end
      end)
    end

    defp binding!(registry, kind, name), do: registry |> Map.fetch!(kind) |> Map.fetch!(name)
  end

  defmodule Microstep do
    @moduledoc false
    use Jido.Flow, name: "statechart_microstep"

    flow do
      step("advance", action: Advance, params: input())
      output(result("advance"))
    end
  end

  flow do
    iterate "stabilize" do
      state(Jido.Joi.map(), initial: input())
      flow(Microstep)
      params(state())
      while(state(:pending) == true)
      max_iterations(100)
    end

    output(result("stabilize"))
  end

  def run(chart, registry, session, input_event, finalize \\ []) do
    {event, internal} =
      case input_event do
        {:platform, event} -> {nil, :queue.in(SCXML.event(event), :queue.new())}
        :cancel -> {nil, :queue.new()}
        event -> {SCXML.event(event), :queue.new()}
      end

    input = %{
      chart: chart,
      registry: registry,
      session: %{session | event: event || SCXML.event(session.event)},
      event: event,
      internal: internal,
      finalize: finalize,
      entered: MapSet.new(),
      ready_invokes: %{},
      cancel: input_event == :cancel,
      effects: [],
      pending: true
    }

    with {:ok, %{state: %{pending: false, session: stable, effects: effects, ready_invokes: invokes}}} <-
           Jido.Exec.run(__MODULE__, input) do
      {:ok, stable, Enum.reverse(effects), invokes}
    else
      {:ok, _state} -> {:error, :statechart_microstep_limit}
      {:error, _reason} = error -> error
    end
  end
end

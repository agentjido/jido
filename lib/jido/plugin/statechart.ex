defmodule Jido.Plugin.Statechart do
  @moduledoc "Runs SCXML chart turns and owns the committed session on a Jido Agent."

  use Jido.Plugin

  alias Jido.{Joi, Signal}
  alias Jido.Statechart.{SCXML, Sends, Turn}
  alias Jido.Plugin.Statechart.Effects

  defmodule Commit do
    @moduledoc false
    use Jido.Agent.Directive
    defstruct [:session, effects: []]
  end

  defmodule Route do
    @moduledoc "Agent route for chart Signals."
    use Jido.Action, name: "statechart_route"

    @impl true
    def run(_params, context) do
      prepared = context.plugin_inputs[Jido.Plugin.Statechart].prepared

      with {:ok, commit} <- Jido.Plugin.Statechart.advance(prepared) do
        {:ok, context.agent_state, List.wrap(commit)}
      end
    end
  end

  @impl Jido.Agent.Extension
  def normalize(
        %{
          chart: %{
            initial: initial,
            roots: roots,
            states: states,
            histories: histories,
            data: data
          }
        } = options
      )
      when is_list(initial) and is_list(roots) and is_map(states) and is_map(histories) and
             (is_map(data) or is_list(data)) do
    if is_map(Map.get(options, :registry, %{})),
      do: {:ok, options},
      else: {:error, :statechart_registry_required}
  end

  def normalize(%{chart: module} = options) when is_atom(module) do
    with {:module, ^module} <- Code.ensure_compiled(module),
         true <-
           function_exported?(module, :chart, 0) and function_exported?(module, :registry, 0),
         chart when is_map(chart) <- module.chart() do
      normalize(%{options | chart: chart} |> Map.put(:registry, module.registry()))
    else
      _ ->
        {:error, :statechart_module_required}
    end
  end

  def normalize(_options), do: {:error, :statechart_module_required}

  @doc false
  def agent_definition(name, chart, registry) do
    Jido.Agent.define!(%{
      name: name,
      routes: [%{path: "**", handler: %{kind: :action, target: Route}}],
      plugins: [
        %{id: id(), provider: __MODULE__, vsn: vsn(), data: %{chart: chart, registry: registry}}
      ]
    })
  end

  @impl Jido.Agent.Extension
  def derive_routes(_opts) do
    for path <- [
          "statechart.initialize",
          "statechart.cancel",
          "statechart.effect_error",
          "statechart.child_completed"
        ],
        do: %{path: path, handler: %{kind: :action, target: Route}}
  end

  @impl Jido.Plugin
  def state_spec(_opts), do: {:statechart, Joi.any() |> Joi.default(%{session: nil})}

  @impl Jido.Plugin
  def prepare(input, opts) do
    if Enum.any?(input.route_candidates, &match?(%{handler: %{target: Route}}, &1)) do
      {:ok,
       %{
         chart: Keyword.fetch!(opts, :chart),
         registry: Keyword.get(opts, :registry, %{}),
         signal: input.signal,
         session: input.plugin_state.session,
         owner: input.agent_id
       }}
    else
      {:ok, nil}
    end
  end

  @impl Jido.Plugin
  def directives(_opts), do: [Commit]

  @impl Jido.Plugin
  def reduce(reduction, _opts) do
    case Enum.find(reduction.directives, &match?(%Commit{}, &1)) do
      %Commit{session: session} -> {:ok, %{session: session}}
      nil -> {:ok, reduction.plugin_state}
    end
  end

  @impl Jido.Plugin
  def child_spec(init), do: Supervisor.child_spec({Sends, init}, id: init.module)

  @impl Jido.Plugin
  def dispatch(runtime, %Commit{session: session, effects: effects}, context, _opts),
    do: Effects.dispatch(runtime, session, effects, context)

  @doc false
  def advance(%{
        chart: chart,
        registry: registry,
        session: nil,
        signal: %Signal{type: "statechart.initialize", data: %{data: data, parent: parent}} = signal,
        owner: owner
      })
      when is_map(data) and (is_nil(parent) or is_map(parent)) do
    root_keys = Map.get_lazy(chart, :root_data_keys, fn -> Enum.map(chart.data, &elem(&1, 0)) end)

    session = %{
      state: nil,
      configuration: [],
      history: %{},
      status: :active,
      event: nil,
      data: Map.take(data, root_keys),
      completion: nil,
      invocations: %{},
      http_location: Map.get(signal.data, :http_location),
      parent: parent,
      owner: owner
    }

    stabilize(chart, registry, session, nil, [])
  end

  def advance(%{session: nil, signal: %Signal{type: "statechart.initialize"}}),
    do: {:error, :invalid_statechart_initialization}

  def advance(%{signal: %Signal{type: "statechart.initialize"}}),
    do: {:error, :statechart_already_initialized}

  def advance(%{session: nil}), do: {:error, :statechart_not_initialized}

  def advance(%{session: %{status: status}}) when status in [:completed, :cancelled],
    do: {:ok, nil}

  def advance(%{
        chart: chart,
        registry: registry,
        session: session,
        signal: %Signal{type: "statechart.cancel"}
      }) do
    stabilize(chart, registry, session, :cancel, [])
  end

  def advance(%{
        chart: chart,
        registry: registry,
        session: session,
        signal: %Signal{type: "statechart.effect_error", data: %{event: event}} = signal
      }) do
    event = %{name: event, type: "platform", data: %{}}
    event = if sendid = signal.data[:sendid], do: Map.put(event, :sendid, sendid), else: event

    case signal.data do
      %{child: child} ->
        case take_invocation(session, &(&1.child == child)) do
          {:ok, _invocation, session} ->
            stabilize(chart, registry, session, {:platform, event}, [])

          nil ->
            {:ok, nil}
        end

      _ ->
        stabilize(chart, registry, session, {:platform, event}, [])
    end
  end

  def advance(%{
        chart: chart,
        registry: registry,
        session: session,
        signal: %Signal{
          type: "statechart.child_completed",
          data: %{child: child, id: id, messages: messages, value: value}
        }
      }) do
    if find_invocation(session, &(&1.id == id and &1.child == child)) do
      done =
        Signal.new!("done.invoke." <> id, %{child: child, value: value}, source: "/statechart")

      replies = Enum.map(messages, &Effects.event_signal(&1, child))

      Enum.reduce_while(replies ++ [done], {:ok, %Commit{session: session}}, fn
        signal, {:ok, %Commit{session: session, effects: effects}} ->
          result =
            case signal do
              ^done -> receive_done(chart, registry, session, signal, true)
              _ -> receive_event(chart, registry, session, signal, true)
            end

          commit =
            case result do
              {:ok, %Commit{} = commit} -> commit
              {:error, _reason} -> child_event_error(chart, registry, session, [])
            end

          commit = %{commit | effects: deliverable(effects ++ commit.effects, commit.session)}

          if commit.session.status == :active,
            do: {:cont, {:ok, commit}},
            else: {:halt, {:ok, commit}}
      end)
    else
      {:ok, nil}
    end
  end

  def advance(%{
        chart: chart,
        registry: registry,
        session: session,
        signal: %Signal{type: "done.invoke." <> _, data: %{child: _, value: _}} = signal
      }) do
    receive_done(chart, registry, session, signal, false)
  end

  def advance(%{chart: chart, registry: registry, session: session, signal: signal}) do
    receive_event(chart, registry, session, signal, false)
  end

  defp receive_done(chart, registry, session, signal, admitted?) do
    %Signal{type: "done.invoke." <> id, data: %{child: child, value: value}} = signal
    event = %{name: signal.type, type: "external", data: value, invokeid: id}

    if Signal.get_context(signal, "scxmlforwarded") do
      stabilize(chart, registry, session, event, forward_effects(session, signal))
    else
      case take_invocation(session, &(&1.id == id and &1.child == child)) do
        {:ok, invocation, session} ->
          effects = forward_effects(session, signal) ++ [{:stop, child}]

          case stabilize(
                 chart,
                 registry,
                 session,
                 event,
                 effects,
                 Map.get(invocation, :finalize, [])
               ) do
            {:error, _reason} when admitted? ->
              {:ok, child_event_error(chart, registry, session, effects)}

            result ->
              result
          end

        nil when admitted? ->
          stabilize(chart, registry, session, event, forward_effects(session, signal))

        nil ->
          {:ok, nil}
      end
    end
  end

  defp child_event_error(chart, registry, session, effects) do
    error = %{name: "error.execution", type: "platform", data: %{}}

    case stabilize(chart, registry, session, {:platform, error}, effects) do
      {:ok, commit} -> commit
      {:error, _reason} -> %Commit{session: session, effects: effects}
    end
  end

  defp receive_event(chart, registry, session, signal, admitted?) do
    data =
      if Signal.get_context(signal, "scxmlcontent") == true,
        do: signal.data[:content],
        else: signal.data

    event = %{name: signal.type, type: "external", data: data}
    origin = Signal.get_context(signal, "scxmlorigin")
    event = if origin, do: Map.merge(event, %{origin: origin, origintype: "scxml"}), else: event
    sendid = Signal.get_context(signal, "scxmlsendid")
    event = if sendid, do: Map.put(event, :sendid, sendid), else: event
    invokeid = Signal.get_context(signal, "scxmlinvokeid")
    event = if invokeid, do: Map.put(event, :invokeid, invokeid), else: event
    method = Signal.get_context(signal, "scxmlhttpmethod")

    event =
      if method,
        do:
          Map.merge(event, %{
            http_method: method,
            http_name: Signal.get_context(signal, "scxmlhttpname")
          }),
        else: event

    if invokeid && !Signal.get_context(signal, "scxmlforwarded") do
      case find_invocation(session, &(&1.id == invokeid and SCXML.location(&1.child) == origin)) do
        nil when admitted? ->
          stabilize(chart, registry, session, event, forward_effects(session, signal))

        nil ->
          {:ok, nil}

        invocation ->
          effects = forward_effects(session, signal)
          stabilize(chart, registry, session, event, effects, Map.get(invocation, :finalize, []))
      end
    else
      stabilize(chart, registry, session, event, forward_effects(session, signal))
    end
  end

  defp forward_effects(session, signal) do
    {:ok, forwarded} = Signal.put_context(signal, "scxmlforwarded", true)

    for state <- session.configuration,
        %{child: child, forward: true} <- List.wrap(session.invocations[state]),
        do: {:send, child, forwarded}
  end

  @doc false
  def find_invocation(session, predicate) do
    Enum.find_value(session.invocations, fn {_state, records} ->
      Enum.find(List.wrap(records), predicate)
    end)
  end

  defp take_invocation(session, matches?) do
    Enum.find_value(session.invocations, fn {state, records} ->
      case Enum.split_with(List.wrap(records), matches?) do
        {[], _remaining} ->
          nil

        {[record], remaining} ->
          invocations = put_invocations(session.invocations, state, remaining)
          {:ok, record, %{session | invocations: invocations}}
      end
    end)
  end

  defp put_invocations(invocations, state, []), do: Map.delete(invocations, state)
  defp put_invocations(invocations, state, [record]), do: Map.put(invocations, state, record)
  defp put_invocations(invocations, state, records), do: Map.put(invocations, state, records)

  defp stabilize(chart, registry, session, event, effects, finalize \\ []) do
    with {:ok, stable, sends, invokes} <- Turn.run(chart, registry, session, event, finalize) do
      stops =
        for state <- Enum.reverse(session.configuration),
            %{child: child} <- List.wrap(session.invocations[state]),
            not Map.has_key?(stable.invocations, state),
            do: {:stop, child}

      {stable, changes} = invoke(registry, stable, invokes)
      effects = effects ++ deliverable(sends, stable) ++ stops ++ changes
      {:ok, %Commit{session: stable, effects: effects}}
    end
  end

  defp deliverable(sends, %{status: :active}), do: sends

  defp deliverable(sends, %{owner: owner}) do
    Enum.reject(sends, fn
      {:send_event, receiver, _event, delay} -> receiver == owner or delay > 0
      {:http_post, _target, _event, delay} -> delay > 0
      _effect -> false
    end)
  end

  defp invoke(_registry, %{status: :completed} = session, _entered) do
    effects = if session.parent, do: [{:done, session.parent, session.completion}], else: []
    {session, effects}
  end

  defp invoke(_registry, %{status: :cancelled} = session, _entered),
    do: {session, []}

  defp invoke(registry, session, invokes) do
    starts =
      for state <- session.configuration,
          %{invocation: invocation, source: source, data: data} <-
            Enum.reverse(Map.get(invokes, state, [])) do
        {state, invocation, resolve_invoke(source, registry), data}
      end

    invocations =
      starts
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce(session.invocations, fn {state, records}, acc ->
        put_invocations(acc, state, records)
      end)

    effects =
      for {_state, invocation, agent, data} <- starts, do: {:start, agent, invocation, data}

    {%{session | invocations: invocations}, effects}
  end

  defp resolve_invoke(%{states: _, initial: _} = chart, registry),
    do: agent_definition("scxml_child", chart, registry)

  defp resolve_invoke(agent, _registry), do: agent
end

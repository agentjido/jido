# This example prints results for its user.
# credo:disable-for-this-file Credo.Check.Warning.IoInspect

defmodule Jido.Examples.Factory.IEx do
  @moduledoc "An IEx session for live conversation, a three-Agent workshop, or a department factory."
  alias Jido.AgentServer, as: Server
  alias Jido.Examples.Factory.{Conversation, Error, LiveConversation, Model, Tools}
  alias Jido.Examples.Factory.System, as: Owner
  alias __MODULE__.Observer

  @doc "Starts a demo session. Modes: :conversation, :workshop, :departments."
  def start(mode \\ :conversation, opts \\ [])
      when mode in [:conversation, :workshop, :departments] do
    jido = Keyword.get(opts, :jido, Jido.FactoryDemo)

    with :ok <- ensure_instance(jido),
         {:ok, owner} <- start_owner(jido, mode, Keyword.get(opts, :id, Jido.ID.uuid7())) do
      id = Server.agent(owner).id

      session = %{
        jido: jido,
        owner: owner,
        owner_id: id,
        mode: mode,
        conversation_id: if(mode == :conversation, do: id, else: "#{id}/conversation"),
        factory_id: "#{id}/factory",
        context: Keyword.get(opts, :context, %{}) |> Map.put_new(:stream, true)
      }

      {:ok, observer} = Observer.start_link(session)

      context =
        Map.put_new(
          session.context,
          :on_stream,
          Observer.callback(observer, Process.group_leader())
        )

      {:ok, %{session | context: context} |> Map.put(:observer, observer)}
    end
  end

  @doc "Sends text. In system modes the answer and factory events print as they arrive."
  def say(session, text) do
    with pid when is_pid(pid) <- Jido.whereis_agent(session.jido, session.conversation_id) do
      request_id = Jido.ID.uuid7()

      context =
        Map.put(
          session.context,
          :on_stream,
          Observer.callback(session.observer, Process.group_leader())
        )

      if session.mode == :conversation do
        result =
          LiveConversation.chat(pid, request_id, text,
            context: context,
            timeout: 60_000
          )

        if context.stream, do: Observer.finish(session.observer, request_id, result)

        case result do
          {:ok, _agent} when context.stream -> :ok
          {:ok, agent} -> IO.puts("assistant> " <> agent.state.answer)
          {:error, reason} -> {:error, reason}
        end
      else
        case Conversation.ask(pid, request_id, text, context: context) do
          {:ok, _} -> :ok
          error -> error
        end
      end
    else
      nil -> {:error, :conversation_unavailable}
    end
  catch
    :exit, _ -> {:error, :conversation_unavailable}
  end

  @doc "Starts a text prompt. /back returns to IEx and leaves the factory running."
  def chat(session) do
    IO.puts("Model: #{Map.get(session.context, :model, Model.model())}")

    IO.puts(
      "Enter text, /status, /job ID, /events, /pause ID, /resume ID, /cancel ID, /back, or /quit."
    )

    read_line(session)
  end

  defp read_line(session) do
    case IO.gets("you> ") do
      :eof -> :ok
      {:error, reason} -> {:error, reason}
      line -> handle_line(session, String.trim(line))
    end
  end

  defp handle_line(_session, "/back"), do: :ok
  defp handle_line(session, "/quit"), do: stop(session)

  defp handle_line(session, line) do
    result =
      case String.split(line, " ", parts: 2) do
        [""] ->
          :ok

        ["/status"] ->
          IO.inspect(status(session), label: "factory", pretty: true)

        ["/events"] ->
          IO.inspect(events(session), label: "events", pretty: true)

        ["/job", id] ->
          IO.inspect(job(session, id), label: "job", pretty: true)

        [command, id] when command in ["/pause", "/resume", "/cancel"] ->
          operation = %{"/pause" => :pause, "/resume" => :resume, "/cancel" => :cancel}[command]
          control(session, operation, id)

        _ ->
          say(session, line)
      end

    case result do
      {:error, reason} -> IO.puts("request failed: " <> Error.message(reason))
      _ -> :ok
    end

    read_line(session)
  end

  @doc "Returns current factory jobs."
  def status(%{mode: :conversation}), do: {:error, :no_factory}
  def status(session), do: control(session, :status, "")

  @doc "Reads one factory job and its queue position."
  def job(%{mode: :conversation}, _id), do: {:error, :no_factory}
  def job(session, id), do: Tools.inspect_factory(session.jido, session.factory_id, :job, id)

  @doc "Sends a command without a model request."
  def control(%{mode: :conversation}, _, _), do: {:error, :no_factory}

  def control(session, operation, job_id) do
    Tools.command(
      session.jido,
      session.factory_id,
      operation,
      Jido.ID.uuid7(),
      job_id,
      "",
      session.context
    )
  end

  @doc "Returns the conversation's last 100 factory events."
  def events(%{mode: :conversation}), do: []

  def events(session) do
    case Jido.whereis_agent(session.jido, session.conversation_id) do
      nil -> []
      pid -> Server.agent(pid).state.events
    end
  end

  @doc "Stops this session and its Agent tree. Other sessions in the instance remain alive."
  def stop(session) do
    stop_observer(session.observer)

    case Jido.stop_agent(session.jido, session.owner_id) do
      {:error, :not_found} -> :ok
      result -> result
    end
  catch
    :exit, :noproc -> :ok
    :exit, {:noproc, _} -> :ok
  end

  defp stop_observer(nil), do: :ok

  defp stop_observer(observer) do
    GenServer.stop(observer)
  catch
    :exit, :noproc -> :ok
    :exit, {:noproc, _} -> :ok
  end

  defp ensure_instance(jido) do
    case Process.whereis(jido) do
      nil ->
        case Jido.start_link(name: jido) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _ ->
        :ok
    end
  end

  defp start_owner(jido, :conversation, id),
    do: Jido.start_agent(jido, LiveConversation, id: id, exec_opts: [timeout: 50_000])

  defp start_owner(jido, mode, id) do
    with {:ok, pid} <- Jido.start_agent(jido, Owner, id: id) do
      case Owner.boot(pid, mode) do
        {:ok, _} ->
          # The next turn starts after the boot turn's Directives finish.
          with {:ok, _} <- Owner.ready(pid),
               {:ok, _} <- Tools.command(jido, "#{id}/factory", :status, "startup", "", "") do
            {:ok, pid}
          else
            error ->
              Jido.stop_agent(jido, pid)
              error
          end

        {:error, reason} ->
          Jido.stop_agent(jido, pid)
          {:error, reason}
      end
    end
  end
end

defmodule Jido.Examples.Factory.IEx.Observer do
  @moduledoc false
  use GenServer
  alias Jido.AgentServer, as: Server

  def start_link(session), do: GenServer.start_link(__MODULE__, session)

  def callback(observer, device) do
    fn id, event ->
      GenServer.call(observer, {:stream, id, event, device})
    end
  end

  def finish(observer, id, result), do: GenServer.call(observer, {:finish, id, result})

  @impl true
  def init(session) do
    Process.monitor(session.owner)
    send(self(), :poll)

    {:ok,
     %{session: session, events: [], answer_key: nil, stream: nil, device: Process.group_leader()}}
  end

  @impl true
  def handle_call({:stream, id, :start, device}, _from, state) do
    state = close_line(state)
    {:reply, :ok, %{state | device: device, stream: %{id: id, printed: false, line_open: false}}}
  end

  def handle_call({:stream, id, {:delta, text}, _device}, _from, %{stream: %{id: id}} = state)
      when is_binary(text) and text != "" do
    unless state.stream.line_open do
      prefix = if state.session.mode == :conversation, do: "assistant> ", else: "\nassistant> "
      IO.write(state.device, prefix)
    end

    IO.write(state.device, text)
    {:reply, :ok, %{state | stream: %{state.stream | printed: true, line_open: true}}}
  end

  def handle_call({:stream, id, :round_end, _device}, _from, %{stream: %{id: id}} = state),
    do: {:reply, :ok, close_line(state)}

  def handle_call({:stream, _, _, _}, _from, state), do: {:reply, :ok, state}

  def handle_call({:finish, id, result}, _from, %{stream: %{id: id}} = state) do
    state = close_line(state)

    case result do
      {:error, _} when state.stream.printed ->
        IO.puts(state.device, "[partial response; request failed]")

      {:ok, agent} when not state.stream.printed ->
        IO.puts(state.device, "assistant> " <> agent.state.answer)

      _ ->
        :ok
    end

    {:reply, :ok, %{state | stream: nil}}
  end

  def handle_call({:finish, _, _}, _from, state), do: {:reply, :ok, state}

  @impl true
  def handle_info(:poll, state) do
    state = observe(state)
    Process.send_after(self(), :poll, 100)
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, _, _}, state), do: {:stop, :normal, close_line(state)}

  @impl true
  def terminate(_, state) do
    close_line(state)
    :ok
  end

  defp observe(%{session: %{mode: :conversation}} = state), do: state

  defp observe(state) do
    case Jido.whereis_agent(state.session.jido, state.session.conversation_id) do
      nil -> state
      pid -> print_changes(Server.agent(pid).state, state)
    end
  catch
    :exit, _ -> state
  end

  defp print_changes(conversation, state) do
    state =
      Enum.reduce(conversation.events, state, fn event, state ->
        if event.event_id in state.events do
          state
        else
          state = close_line(state)
          IO.puts(state.device, "\n[factory #{event.job_id} #{event.status}] #{event.detail}")
          state
        end
      end)

    key = {length(conversation.messages), conversation.answer, conversation.error}

    state =
      if conversation.status == :idle and key != state.answer_key do
        state = close_line(state)
        printed? = state.stream != nil and state.stream.printed

        cond do
          conversation.error != "" ->
            if printed?, do: IO.puts(state.device, "[partial response; request failed]")
            IO.puts(state.device, "\n[model error] #{conversation.error}")

          conversation.answer != "" and not printed? ->
            IO.puts(state.device, "\nassistant> #{conversation.answer}")

          true ->
            :ok
        end

        %{state | stream: nil}
      else
        state
      end

    %{state | events: Enum.map(conversation.events, & &1.event_id), answer_key: key}
  end

  defp close_line(%{stream: %{line_open: true}} = state) do
    IO.write(state.device, "\n")
    %{state | stream: %{state.stream | line_open: false}}
  end

  defp close_line(state), do: state
end

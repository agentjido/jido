defmodule Jido.AgentServer.Idle do
  @moduledoc false
  alias Jido.AgentServer.State

  def handle_event({:call, from}, {:attach, owner_pid}, _phase, %State{} = data) do
    case attach_owner(data, owner_pid) do
      {:ok, next_data} ->
        {:keep_state, next_data, [{:reply, from, :ok}]}

      {:error, reason} ->
        {:keep_state_and_data, [{:reply, from, {:error, reason}}]}
    end
  end

  def handle_event({:call, from}, {:detach, owner_pid}, phase, %State{} = data) do
    next_data = data |> detach_owner(owner_pid) |> maybe_start_idle_timer(phase)
    {:keep_state, next_data, [{:reply, from, :ok}]}
  end

  def handle_event(:cast, :touch, phase, %State{} = data) do
    {:keep_state, data |> cancel_idle_timer() |> maybe_start_idle_timer(phase)}
  end

  def handle_event(
        :info,
        {:timeout, ref, :agent_idle_timeout},
        :idle,
        %State{idle_timer: ref} = data
      ) do
    {:stop, {:shutdown, :idle_timeout}, %{data | idle_timer: nil}}
  end

  def handle_event(:info, {:timeout, _ref, :agent_idle_timeout}, _phase, %State{}) do
    :keep_state_and_data
  end

  defp attach_owner(%State{} = data, owner_pid) do
    cond do
      owner_pid == self() ->
        {:error, :cannot_attach_self}

      not Process.alive?(owner_pid) ->
        {:error, :owner_not_alive}

      Map.has_key?(data.attachments, owner_pid) ->
        {:ok, cancel_idle_timer(data)}

      true ->
        ref = Process.monitor(owner_pid)

        {:ok,
         %{
           cancel_idle_timer(data)
           | attachments: Map.put(data.attachments, owner_pid, ref)
         }}
    end
  end

  defp detach_owner(%State{} = data, owner_pid) do
    case Map.fetch(data.attachments, owner_pid) do
      {:ok, ref} ->
        Process.demonitor(ref, [:flush])
        remove_attachment(data, owner_pid)

      :error ->
        data
    end
  end

  def remove_attachment(%State{} = data, owner_pid) do
    %{data | attachments: Map.delete(data.attachments, owner_pid)}
  end

  def maybe_start_idle_timer(%State{} = data, phase) when phase != :idle, do: data

  def maybe_start_idle_timer(%State{idle_timeout: :infinity} = data, :idle), do: data

  def maybe_start_idle_timer(%State{idle_timer: timer} = data, :idle)
      when not is_nil(timer),
      do: data

  def maybe_start_idle_timer(%State{} = data, :idle) do
    if map_size(data.attachments) == 0 do
      timer = :erlang.start_timer(data.idle_timeout, self(), :agent_idle_timeout)
      %{data | idle_timer: timer}
    else
      data
    end
  end

  def cancel_idle_timer(%State{idle_timer: nil} = data), do: data

  def cancel_idle_timer(%State{idle_timer: timer} = data) do
    _ = :erlang.cancel_timer(timer)
    %{data | idle_timer: nil}
  end
end

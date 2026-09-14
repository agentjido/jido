defmodule JidoTest.System.RedisServer do
  @moduledoc false
  use GenServer, shutdown: 20_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def command(socket, parts) do
    with_connection(socket, fn connection ->
      :ok = :gen_tcp.send(connection, encode(parts))
      reply(connection)
    end)
  end

  # A one-command TCP proxy receives the real Redis reply, then closes its
  # downstream socket without forwarding it. The adapter receives TCP :closed.
  # It cannot infer the write outcome; the scenario checks storage separately.
  def command_without_reply(socket, parts) do
    {:ok, listener} = :gen_tcp.listen(0, ip: {127, 0, 0, 1}, active: false, mode: :binary)
    {:ok, {_ip, port}} = :inet.sockname(listener)
    expected = IO.iodata_to_binary(encode(parts))

    proxy =
      Task.async(fn ->
        {:ok, downstream} = :gen_tcp.accept(listener, 5_000)

        try do
          {:ok, ^expected} = :gen_tcp.recv(downstream, byte_size(expected), 5_000)
          {:ok, _accepted} = command(socket, parts)
          :ok
        after
          :gen_tcp.close(downstream)
        end
      end)

    try do
      result = command({:tcp, port}, parts)
      :ok = Task.await(proxy, 10_000)
      result
    after
      :gen_tcp.close(listener)
      Task.shutdown(proxy, :brutal_kill)
    end
  end

  defp encode(parts) do
    request = ["*", Integer.to_string(length(parts)), "\r\n"]
    values = Enum.map(parts, &["$", Integer.to_string(byte_size(&1)), "\r\n", &1, "\r\n"])
    [request, values]
  end

  defp with_connection(socket, fun) do
    {address, port} =
      case socket do
        {:tcp, port} -> {{127, 0, 0, 1}, port}
        path -> {{:local, String.to_charlist(path)}, 0}
      end

    with {:ok, connection} <-
           :gen_tcp.connect(address, port,
             mode: :binary,
             active: false,
             packet: :line
           ) do
      try do
        fun.(connection)
      after
        :gen_tcp.close(connection)
      end
    end
  end

  @impl true
  def init({path, observer}) do
    executable =
      System.get_env("JIDO_SYSTEM_REDIS_SERVER") || System.find_executable("redis-server")

    unless executable do
      raise "System Redis tests require redis-server. Set JIDO_SYSTEM_REDIS_SERVER to its executable path."
    end

    case System.cmd(executable, ["--version"], stderr_to_stdout: true) do
      {_version, 0} -> :ok
      {output, status} -> raise "Redis prerequisite failed (exit #{status}): #{output}"
    end

    File.mkdir_p!(path)
    suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    # Unix sockets have a short path limit; ExUnit's per-test path can exceed it.
    socket = Path.join("/tmp", "jido-system-#{suffix}.sock")

    {:ok, launch(executable, path, socket, observer)}
  end

  defp launch(executable, path, socket, observer) do
    port =
      Port.open({:spawn_executable, executable}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 16_384},
        args: [
          "--port",
          "0",
          "--unixsocket",
          socket,
          "--unixsocketperm",
          "700",
          "--dir",
          path,
          "--save",
          "",
          "--appendonly",
          "yes",
          "--appendfsync",
          "always"
        ]
      ])

    Process.flag(:trap_exit, true)
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    JidoTest.System.Observability.service_log(observer, :redis, "Redis started",
      phase: :started,
      os_pid: os_pid
    )

    %{
      executable: executable,
      path: path,
      port: port,
      socket: socket,
      os_pid: os_pid,
      observer: observer,
      ready?: false,
      waiters: [],
      exit_status: nil
    }
  end

  @impl true
  def handle_call(:connection, _from, %{ready?: true} = state),
    do: {:reply, {state.socket, state.os_pid}, state}

  def handle_call(:connection, from, state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_call(:crash_restart, from, state) do
    {_output, 0} =
      System.cmd("kill", ["-KILL", Integer.to_string(state.os_pid)], stderr_to_stdout: true)

    receive do
      {port, {:exit_status, status}} when port == state.port ->
        record_exit(state, status, 137)
    after
      5_000 -> raise "Owned Redis process did not exit after SIGKILL"
    end

    restarted = launch(state.executable, state.path, state.socket, state.observer)
    {:noreply, %{restarted | waiters: [from]}}
  end

  @impl true
  def handle_info({port, {:data, {_ending, line}}}, %{port: port} = state) do
    JidoTest.System.Observability.service_log(state.observer, :redis, line)

    if String.contains?(line, "Ready to accept connections") do
      for waiter <- state.waiters, do: GenServer.reply(waiter, {state.socket, state.os_pid})
      {:noreply, %{state | ready?: true, waiters: []}}
    else
      {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:redis_exit, status}, %{state | exit_status: status}}

  def handle_info({:EXIT, _old_port, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    status = stop_port(state)

    record_exit(state, status, 0)

    File.rm(state.socket)
  end

  defp record_exit(state, status, expected) do
    JidoTest.System.Observability.service_log(state.observer, :redis, "Redis exited",
      exit_status: status,
      expected_exit_status: expected,
      os_pid: state.os_pid
    )
  end

  defp stop_port(%{exit_status: status}) when is_integer(status), do: status

  defp stop_port(state) do
    _ = command(state.socket, ["SHUTDOWN", "NOSAVE"])

    receive do
      {port, {:exit_status, status}} when port == state.port -> status
    after
      5_000 ->
        if Port.info(state.port), do: Port.close(state.port)
        :exit_timeout
    end
  end

  defp reply(connection) do
    case :gen_tcp.recv(connection, 0, 10_000) do
      {:ok, "+" <> value} ->
        {:ok, String.trim_trailing(value, "\r\n")}

      {:ok, ":" <> value} ->
        {:ok, value |> String.trim() |> String.to_integer()}

      {:ok, "$-1\r\n"} ->
        {:ok, nil}

      {:ok, "$" <> size} ->
        length = size |> String.trim() |> String.to_integer()
        :ok = :inet.setopts(connection, packet: :raw)

        with {:ok, bytes} <- :gen_tcp.recv(connection, length + 2, 10_000) do
          {:ok, binary_part(bytes, 0, length)}
        end

      {:ok, "-" <> reason} ->
        {:error, String.trim_trailing(reason, "\r\n")}

      other ->
        other
    end
  end
end

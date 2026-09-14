defmodule JidoTest.System.PostgresRepo do
  @moduledoc false
  use Ecto.Repo, otp_app: :jido, adapter: Ecto.Adapters.Postgres
end

defmodule JidoTest.System.Postgres do
  @moduledoc false
  use GenServer, shutdown: 20_000
  alias JidoTest.System.Observability

  def start_link(observer), do: GenServer.start_link(__MODULE__, observer)

  def init(observer) do
    docker = System.find_executable("docker") || raise "PostgreSQL system tests require Docker"
    image = System.get_env("JIDO_SYSTEM_POSTGRES_IMAGE", "postgres:17-alpine")
    name = "jido-system-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    command!(docker, [
      "run",
      "--detach",
      "--rm",
      "--pull=never",
      "--name",
      name,
      "--label",
      "jido.system-test=true",
      "--publish",
      "127.0.0.1::5432",
      "--env",
      "POSTGRES_PASSWORD=jido-system-only",
      "--env",
      "POSTGRES_DB=jido_system",
      image
    ])

    try do
      address = command!(docker, ["port", name, "5432/tcp"]) |> String.trim()
      ["127.0.0.1", port] = String.split(address, ":")
      port = String.to_integer(port)
      Process.flag(:trap_exit, true)

      logs =
        Port.open({:spawn_executable, docker}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          {:line, 16_384},
          args: ["logs", "--follow", name]
        ])

      {:ok,
       %{
         docker: docker,
         name: name,
         port: port,
         logs: logs,
         observer: observer,
         initialized?: false,
         ready?: false,
         waiters: []
       }}
    rescue
      error ->
        command!(docker, ["stop", "--time", "5", name])
        reraise error, __STACKTRACE__
    end
  end

  def handle_call(:connection, _from, %{ready?: true} = state),
    do: {:reply, options(state), state}

  def handle_call(:connection, from, state),
    do: {:noreply, %{state | waiters: [from | state.waiters]}}

  def handle_info({port, {:data, {_ending, line}}}, %{logs: port} = state) do
    Observability.service_log(state.observer, :postgres, line)

    initialized? =
      state.initialized? or String.contains?(line, "PostgreSQL init process complete")

    ready? =
      initialized? and String.contains?(line, "database system is ready to accept connections")

    state = %{state | initialized?: initialized?}

    if ready? do
      for waiter <- state.waiters, do: GenServer.reply(waiter, options(state))
      {:noreply, %{state | ready?: true, waiters: []}}
    else
      {:noreply, state}
    end
  end

  def handle_info({port, {:exit_status, status}}, %{logs: port} = state),
    do: {:stop, {:postgres_log_process_exited, status}, state}

  # System.cmd ports can deliver their normal EXIT after init enables trapping.
  # The followed log port has its own explicit exit_status clause above.
  def handle_info({:EXIT, port, :normal}, state) when is_port(port), do: {:noreply, state}

  def terminate(_reason, state) do
    command!(state.docker, ["stop", "--time", "5", state.name])

    {_output, status} =
      System.cmd(state.docker, ["container", "inspect", state.name], stderr_to_stdout: true)

    if status == 0, do: raise("Owned PostgreSQL container survived cleanup: #{state.name}")

    receive do
      {port, {:exit_status, 0}} when port == state.logs -> :ok
    after
      5_000 -> raise "PostgreSQL log process did not stop"
    end

    Observability.service_log(state.observer, :postgres, "Owned container removed",
      container: state.name
    )
  end

  defp options(state),
    do: [
      hostname: "127.0.0.1",
      port: state.port,
      username: "postgres",
      password: "jido-system-only",
      database: "jido_system",
      pool_size: 4,
      log: false
    ]

  defp command!(docker, args) do
    case System.cmd(docker, args, stderr_to_stdout: true) do
      {output, 0} ->
        output

      {output, status} ->
        raise "PostgreSQL Docker prerequisite/operation failed (#{status}): #{output}"
    end
  end
end

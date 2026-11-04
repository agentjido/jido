defmodule Jido.Test.External.Docker do
  @moduledoc false

  import ExUnit.Assertions

  def start!(image, container_port, opts, on_exit)
      when is_binary(image) and is_integer(container_port) and is_function(on_exit, 1) do
    docker = System.find_executable("docker") || raise "service tests require Docker"
    name = "jido-service-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

    env =
      opts
      |> Keyword.get(:env, [])
      |> Enum.flat_map(fn {key, value} -> ["--env", "#{key}=#{value}"] end)

    args =
      [
        "run",
        "--detach",
        "--rm",
        "--pull=never",
        "--name",
        name,
        "--label",
        "jido.service-test=true",
        "--publish",
        "127.0.0.1::#{container_port}"
      ] ++ env ++ [image] ++ Keyword.get(opts, :command, [])

    command!(docker, args)

    on_exit.(fn ->
      {_output, _status} = System.cmd(docker, ["stop", "--time", "5", name], stderr_to_stdout: true)

      {_output, status} =
        System.cmd(docker, ["container", "inspect", name], stderr_to_stdout: true)

      assert status != 0, "owned service container survived cleanup: #{name}"
    end)

    port = mapped_port!(docker, name, container_port)
    wait_for_tcp!(port)
    %{docker: docker, name: name, port: port}
  end

  defp mapped_port!(docker, name, container_port) do
    output = command!(docker, ["port", name, "#{container_port}/tcp"]) |> String.trim()
    ["127.0.0.1", port] = String.split(output, ":")
    String.to_integer(port)
  end

  defp wait_for_tcp!(port) do
    deadline = System.monotonic_time(:millisecond) + 30_000
    connect_until(port, deadline)
  end

  defp connect_until(port, deadline) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 250) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _reason} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "service did not accept TCP connections on localhost:#{port}"
        end

        receive do
        after
          25 -> connect_until(port, deadline)
        end
    end
  end

  defp command!(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> raise "Docker service operation failed (#{status}): #{output}"
    end
  end
end

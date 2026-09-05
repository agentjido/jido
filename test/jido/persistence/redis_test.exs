defmodule JidoTest.Persistence.RedisTest do
  use ExUnit.Case, async: true

  alias Jido.Persistence.Redis

  defp start_store do
    {:ok, pid} = Elixir.Agent.start_link(fn -> %{data: %{}, commands: []} end)
    pid
  end

  defp command_fn(pid, override \\ fn _command -> :next end) do
    fn command ->
      case override.(command) do
        :next -> handle_command(pid, command)
        result -> result
      end
    end
  end

  defp handle_command(pid, command) do
    Elixir.Agent.get_and_update(pid, fn state ->
      state = update_in(state.commands, &[command | &1])

      case command do
        ["GET", key] -> {{:ok, Map.get(state.data, key)}, state}
        ["SET", key, value] -> {{:ok, "OK"}, put_in(state.data[key], value)}
        ["SET", key, value, "PX", _ttl] -> {{:ok, "OK"}, put_in(state.data[key], value)}
        ["DEL", key] -> {{:ok, 1}, update_in(state.data, &Map.delete(&1, key))}
      end
    end)
  end

  defp opts(pid, extra \\ []), do: Keyword.merge([command_fn: command_fn(pid)], extra)

  test "gets, replaces, and deletes binary values" do
    pid = start_store()
    opts = opts(pid)

    assert {:error, :not_found} = Redis.get("key", opts)
    assert :ok = Redis.put("key", <<1>>, opts)
    assert {:ok, <<1>>} = Redis.get("key", opts)
    assert :ok = Redis.put("key", <<2>>, opts)
    assert {:ok, <<2>>} = Redis.get("key", opts)
    assert :ok = Redis.delete("key", opts)
    assert {:error, :not_found} = Redis.get("key", opts)
  end

  test "uses the configured prefix and TTL" do
    pid = start_store()
    opts = opts(pid, prefix: "custom", ttl: 60_000)

    assert :ok = Redis.put("key", "value", opts)

    assert [["SET", "custom:key", "value", "PX", "60000"]] =
             pid |> Elixir.Agent.get(&Enum.reverse(&1.commands))
  end

  test "requires a command function" do
    assert_raise ArgumentError, ~r/requires a :command_fn/, fn ->
      Redis.get("key", [])
    end
  end

  test "compares binary values in one EVAL command with prefix and TTL" do
    observer = self()

    command_fn = fn command ->
      send(observer, {:command, command})
      {:ok, 1}
    end

    opts = [command_fn: command_fn, prefix: "custom", ttl: 60_000]
    assert :ok = Redis.compare_and_swap("key", <<0, 255>>, <<1, 0>>, opts)

    assert_receive {:command,
                    ["EVAL", script, "1", "custom:key", "value", <<0, 255>>, <<1, 0>>, "60000"]}

    assert :ok = Redis.compare_and_swap("key", :not_found, <<1>>, command_fn: command_fn)
    assert_receive {:command, ["EVAL", ^script, "1", "jido:key", "missing", "", <<1>>, ""]}
  end

  test "maps atomic write conflicts and rejects invalid replies" do
    assert {:error, :conflict} =
             Redis.compare_and_swap("key", :not_found, "value", command_fn: fn _ -> {:ok, 0} end)

    for reply <- [{:ok, "OK"}, {:ok, nil}, :invalid] do
      assert {:error, {:indeterminate, {:invalid_redis_result, ^reply}}} =
               Redis.compare_and_swap("key", :not_found, "value", command_fn: fn _ -> reply end)
    end
  end

  test "rejects an invalid TTL before it sends a conditional write" do
    observer = self()

    for ttl <- [0, -1, "1000"] do
      assert_raise ArgumentError, ~r/:ttl must be a positive integer/, fn ->
        Redis.compare_and_swap("key", :not_found, "value",
          ttl: ttl,
          command_fn: fn command -> send(observer, {:unexpected, command}) end
        )
      end
    end

    refute_receive {:unexpected, _}
  end

  test "propagates Redis command errors" do
    failing = [command_fn: fn _command -> {:error, :connection_closed} end]

    assert {:error, :connection_closed} = Redis.get("key", failing)
    assert {:error, :connection_closed} = Redis.put("key", "value", failing)

    assert {:error, {:indeterminate, :connection_closed}} =
             Redis.compare_and_swap("key", :not_found, "value", failing)

    assert {:error, :connection_closed} = Redis.delete("key", failing)
  end
end

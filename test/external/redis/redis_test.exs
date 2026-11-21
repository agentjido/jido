Code.require_file("../support/docker.exs", __DIR__)
Code.require_file("support.exs", __DIR__)

defmodule Jido.Persistence.External.RedisTest do
  use Jido.Test.Case, async: false

  @moduletag :service
  @moduletag timeout: 120_000

  use Jido.Test.Persistence.Contracts.Store

  setup_all do
    container =
      Jido.Test.External.Docker.start!(
        "redis:7-alpine",
        6379,
        [command: ["redis-server", "--save", "", "--appendonly", "no"]],
        &on_exit/1
      )

    assert {:ok, "PONG"} = Jido.Test.External.RedisClient.command(container.port, ["PING"])

    store =
      {Jido.Persistence.Redis,
       command_fn: &Jido.Test.External.RedisClient.command(container.port, &1), prefix: "jido-system"}

    {:ok, store: store}
  end
end

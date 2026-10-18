defmodule Jido.Examples.Durable.VMRecovery do
  @moduledoc "The application owns the DETS adapter before it starts Jido."
  use Supervisor
  alias Jido.Examples.Durable.VMRecovery.DetsStore

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    table = __MODULE__.Checkpoints

    children = [
      {DetsStore, table: table, path: Keyword.fetch!(opts, :path)},
      {Jido,
       name: __MODULE__.Instance,
       namespace: "examples/durable/vm_recovery",
       persistence: {DetsStore, server: table}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

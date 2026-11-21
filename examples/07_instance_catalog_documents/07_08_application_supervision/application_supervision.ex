defmodule Jido.Examples.ApplicationSupervision.InstalledAgent do
  @moduledoc "An installed Agent definition started by application bootstrap."

  use Jido.Agent, name: "application_supervision_installed_agent"

  state do
    schema Jido.Joi.object(%{ready: Jido.Joi.boolean() |> Jido.Joi.default(true)})
  end
end

defmodule Jido.Examples.ApplicationSupervision.Bootstrap do
  @moduledoc "Starts required application Agents after the Jido instance starts."
  use GenServer

  alias Jido.Examples.ApplicationSupervision.InstalledAgent

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    instance = Keyword.fetch!(opts, :instance)

    case Jido.start_agent(instance, InstalledAgent, id: "installed-agent") do
      {:ok, server} -> {:ok, %{instance: instance, server: server}}
      {:error, reason} -> {:stop, reason}
    end
  end
end

defmodule Jido.Examples.ApplicationSupervision do
  @moduledoc "A host application supervisor that owns Jido and its bootstrap."
  use Supervisor

  alias Jido.Examples.ApplicationSupervision.Bootstrap

  def start_link(opts),
    do: Supervisor.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))

  @impl true
  def init(opts) do
    instance = Keyword.fetch!(opts, :instance)
    namespace = Keyword.fetch!(opts, :namespace)

    children = [
      {Jido, name: instance, namespace: namespace},
      {Bootstrap, instance: instance}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

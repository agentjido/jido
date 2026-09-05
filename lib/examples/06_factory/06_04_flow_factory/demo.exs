defmodule Jido.Examples.Factory.FlowFactory.Demo do
  @moduledoc false
  alias Jido.Examples.Factory.FlowFactory

  def run do
    {opts, words, invalid} =
      OptionParser.parse(System.argv(),
        strict: [live: :boolean, security: :boolean, accept_after: :integer, fail_role: :string]
      )

    if invalid != [], do: raise(ArgumentError, "Unknown options: #{inspect(invalid)}")
    live? = Keyword.get(opts, :live, false)

    if live? do
      case Dotenvy.source([Path.expand("../../../../.env", __DIR__), System.get_env()]) do
        {:ok, variables} -> System.put_env(variables)
        {:error, _} -> raise "Cannot load the project .env file"
      end
    end

    goal =
      if words == [],
        do: "Design CSV export for a support ticket application",
        else: Enum.join(words, " ")

    IO.puts(
      if live?,
        do: "Live model: #{Jido.Examples.Factory.Model.model()}",
        else: "Local demonstration: no model key needed"
    )

    IO.puts(
      "Research + Design -> API / UI / Tests -> Integration -> Quality + Security -> repair (at most twice) -> Handoff"
    )

    {:ok, instance} = Jido.start_link(name: __MODULE__)

    try do
      {:ok, mission} =
        FlowFactory.start(__MODULE__, goal,
          security: Keyword.get(opts, :security, true),
          context: %{
            mode: if(live?, do: :live, else: :fixture),
            accept_after: Keyword.get(opts, :accept_after, 1),
            fail_role: opts[:fail_role]
          }
        )

      show(mission, 0)
    after
      Supervisor.stop(instance)
    end
  end

  defp show(mission, seen) do
    state = FlowFactory.status(mission)

    Enum.each(Enum.drop(state.events, seen), fn event ->
      IO.puts("#{event.sequence}. #{event.role} revision #{event.revision}: #{event.status}")
    end)

    if state.status == :running do
      receive do
      after
        100 -> show(mission, length(state.events))
      end
    else
      IO.puts("\nMission: #{state.status}; #{map_size(state.artifacts)} committed artifacts")

      if state.status == :completed,
        do: IO.puts("\n" <> state.output.handoff.text),
        else: IO.puts(state.error)

      if state.status == :completed, do: 0, else: 1
    end
  end
end

System.halt(Jido.Examples.Factory.FlowFactory.Demo.run())

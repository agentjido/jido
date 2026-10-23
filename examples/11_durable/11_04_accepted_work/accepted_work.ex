defmodule Jido.Examples.Durable.AcceptedWork do
  @moduledoc "Runs one report Flow as the current durable Turn."
  use Jido.Agent, name: "durable_accepted_work"

  state do
    schema Zoi.object(%{report: Zoi.string() |> Zoi.default("")})
  end

  routes do
    signal_source "/examples/durable/accepted_work"

    route "examples.durable.accepted_work.request", Jido.Examples.Durable.AcceptedWork.Report,
      as: :request
  end
end

defmodule Jido.Examples.Durable.AcceptedWork.Report do
  @moduledoc "A report Flow whose accepted input is portable data."
  use Jido.Flow,
    name: "durable_accepted_report",
    schema: Zoi.object(%{topic: Zoi.string()}),
    output_schema: Zoi.object(%{report: Zoi.string()})

  flow do
    step "normalize", topic <- input(:topic) do
      {:ok, %{topic: String.trim(topic)}}
    end

    step "render", topic <- result("normalize", :topic) do
      {:ok, %{report: "Report: " <> topic}}
    end

    output result("render")
  end
end

defmodule Jido.Examples.Durable.AcceptedWork.Team do
  @moduledoc "A persistent topology owns the report Agent and restores its current Turn."
  use Jido.Agent, name: "durable_report_team"

  topology do
    agent :reports, Jido.Examples.Durable.AcceptedWork
  end
end

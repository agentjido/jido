defmodule Jido.Examples.Durable.AcceptedWork do
  @moduledoc "Runs one report Flow as the current durable Turn."
  use Jido.Agent, name: "durable_accepted_work"

  state do
    schema Jido.Joi.object(%{report: Jido.Joi.string() |> Jido.Joi.default("")})
  end

  routes do
    signal_source "/examples/durable/accepted_work"

    route "examples.durable.accepted_work.request", Jido.Examples.Durable.AcceptedWork.Report, as: :request do
    end
  end
end

defmodule Jido.Examples.Durable.AcceptedWork.Report do
  @moduledoc "A report Flow whose accepted input is portable data."
  use Jido.Flow,
    name: "durable_accepted_report",
    schema: Jido.Joi.object(%{topic: Jido.Joi.string()}),
    output_schema: Jido.Joi.object(%{report: Jido.Joi.string()})

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

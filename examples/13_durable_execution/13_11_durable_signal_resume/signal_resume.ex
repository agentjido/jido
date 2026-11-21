defmodule Jido.Examples.Durability.SignalResume do
  @moduledoc "Resumes one wait from a host-created cron occurrence Signal."
  use Jido.Flow, name: "example_durable_signal_resume"

  flow do
    await "tick",
      event: "examples.durable.cron.tick",
      match: %{report: input(:report)}

    output result("tick")
  end
end

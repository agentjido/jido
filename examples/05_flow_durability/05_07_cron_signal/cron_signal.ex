defmodule Jido.Examples.Durability.CronSignal do
  @moduledoc "Waits for one cron occurrence Signal from a host."
  use Jido.Flow, name: "example_durable_cron_signal"

  flow do
    await "tick",
      event: "examples.durable.cron.tick",
      match: %{report: input(:report)}

    output result("tick")
  end
end

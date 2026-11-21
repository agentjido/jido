defmodule Jido.Examples.Durability.TimedResume do
  @moduledoc "Resumes one saved timer when its host reaches the wake time."
  use Jido.Flow, name: "example_durable_timed_resume"

  flow do
    timer "wake", after_ms: 60_000
    output result("wake")
  end
end

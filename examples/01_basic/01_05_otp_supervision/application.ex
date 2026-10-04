defmodule Jido.Examples.OTPSupervision.Jido do
  @moduledoc "The application-owned Jido instance and its Agent lifecycle facade."
  use Jido,
    otp_app: :jido,
    namespace: "jido/examples/otp-supervision"
end

defmodule Jido.Examples.OTPSupervision.Application do
  @moduledoc "An ordinary OTP application with a directly supervised Agent."
  use Application

  alias Jido.Examples.OTPSupervision.Counter

  @impl true
  def start(_type, opts) do
    jido = Keyword.get(opts, :jido, Jido.Examples.OTPSupervision.Jido)

    children = [
      jido,
      Supervisor.child_spec(
        {Jido.AgentServer, jido: jido, agent: Counter, id: "otp-counter", restart: :transient},
        id: :counter
      )
    ]

    # Start infrastructure first and stop the Agent first. If infrastructure
    # is lost, rest_for_one also replaces the dependent Agent.
    Supervisor.start_link(children, strategy: :rest_for_one, max_restarts: 3, max_seconds: 5)
  end
end

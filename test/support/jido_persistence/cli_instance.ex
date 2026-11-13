defmodule Jido.Test.Persistence.CLIInstance do
  @moduledoc false

  use Jido,
    otp_app: :jido,
    namespace: "mix-task-instance",
    persistence: {Jido.Persistence.ETS, table: :mix_task_instance}
end

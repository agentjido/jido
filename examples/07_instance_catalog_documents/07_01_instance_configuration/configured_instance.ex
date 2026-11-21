defmodule Jido.Examples.ConfiguredInstance do
  @moduledoc """
  A named Jido instance for a host OTP application.

  `use Jido` fixes the instance name and reads application configuration. The
  host supervisor can still pass runtime overrides to `start_link/1`.
  """

  use Jido,
    otp_app: :jido,
    namespace: "examples/configured-instance"
end

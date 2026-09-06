defmodule Jido.Examples.RecursiveLanguageModel.Fixtures do
  @moduledoc "Reproducible log records for the RLM example and stress runner."

  def logs(count, opts \\ []) when is_integer(count) and count >= 0 do
    payload = String.duplicate("x", Keyword.get(opts, :payload_bytes, 64))
    services = Keyword.get(opts, :services, 7)

    if count == 0 do
      []
    else
      for index <- 0..(count - 1) do
        %{
          id: "job-#{index}",
          service: "service-#{rem(index, services)}",
          status: if(rem(index, 5) == 0, do: :failed, else: :ok),
          message: payload
        }
      end
    end
  end
end

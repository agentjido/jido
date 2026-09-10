defmodule Jido.Examples.ApprovalWorkflow.SubmitBooking do
  @moduledoc "A portable post-commit booking request owned by the booking Plugin."

  @schema Zoi.struct(
            __MODULE__,
            %{
              request: Zoi.map(),
              idempotency_key: Zoi.string() |> Zoi.min(1)
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema
end

defmodule Jido.Examples.ApprovalWorkflow.BookingPlugin do
  @moduledoc "Dispatches typed booking requests without a Plugin process."

  use Jido.Plugin

  alias Jido.AgentServer, as: Server
  alias Jido.Examples.ApprovalWorkflow.SubmitBooking
  alias Jido.Signal

  @doc "Creates one portable booking submission Directive."
  @spec submit(map(), String.t()) :: SubmitBooking.t()
  def submit(request, idempotency_key) do
    %SubmitBooking{request: request, idempotency_key: idempotency_key}
  end

  @impl true
  def directives(_opts), do: [SubmitBooking]

  @impl true
  def validate_directive(%SubmitBooking{} = directive, _opts) do
    Zoi.parse(SubmitBooking.schema(), Map.from_struct(directive))
  end

  @impl true
  def dispatch(nil, %SubmitBooking{} = directive, context, _opts) do
    {module, client} = context.turn_context.booking_adapter

    server = Jido.whereis_agent(context.jido, context.agent_id, partition: context.partition)

    signal =
      case module.book(client, directive.request, directive.idempotency_key) do
        {:ok, booking_id} ->
          Signal.new!(
            "examples.flight.booking_succeeded",
            %{booking_key: directive.idempotency_key, booking_id: booking_id},
            source: "/examples/flight_booking/plugin"
          )

        {:error, reason} ->
          Signal.new!(
            "examples.flight.booking_failed",
            %{booking_key: directive.idempotency_key, reason: inspect(reason)},
            source: "/examples/flight_booking/plugin"
          )
      end

    Server.cast(server, signal)
  end
end

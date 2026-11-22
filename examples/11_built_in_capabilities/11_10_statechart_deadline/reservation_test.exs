Code.require_file("reservation.ex", __DIR__)

defmodule Jido.Examples.Statechart.ReservationTest do
  use Jido.Test.Case, async: true

  alias Jido.Examples.Statechart.Reservation
  alias Jido.Statechart

  @moduletag :integration
  @hold_duration "500ms"

  test "confirmation cancels the deadline while an unconfirmed reservation expires", %{jido: jido} do
    confirmed_id = unique_id("confirmed-reservation")
    expired_id = unique_id("unconfirmed-reservation")
    observer = make_ref()

    turn = [:jido, :agent_server, :turn]

    :ok =
      :telemetry.attach_many(
        observer,
        [turn ++ [:start], turn ++ [:settled]],
        &__MODULE__.record_deadline/4,
        {self(), confirmed_id, expired_id}
      )

    try do
      confirmed = hold_stock(jido, confirmed_id)
      assert {:ok, %{status: :committed}} = Reservation.confirm(confirmed)
      assert %{state: "confirmed", status: :active} = Statechart.session(confirmed)

      expired = hold_stock(jido, expired_id)
      assert_receive {:deadline_delivered, ^expired_id}, 2_000
      assert %{state: "expired", status: :completed} = Statechart.session(expired)

      refute_receive {:deadline_delivered, ^confirmed_id}, 100
      assert %{state: "confirmed", status: :active} = Statechart.session(confirmed)
      assert :ok = Jido.stop_agent(jido, confirmed)
      assert :ok = Jido.stop_agent(jido, expired)
      refute Process.alive?(confirmed)
      refute Process.alive?(expired)
    after
      :telemetry.detach(observer)
    end
  end

  def record_deadline(event, _measurements, %{signal_type: "examples.reservation.deadline", agent_id: id}, config) do
    case {List.last(event), config} do
      {:start, {pid, ^id, _expired}} -> send(pid, {:deadline_delivered, id})
      {:settled, {pid, _confirmed, ^id}} -> send(pid, {:deadline_delivered, id})
      _other -> :ok
    end
  end

  def record_deadline(_event, _measurements, _metadata, _config), do: :ok

  defp hold_stock(jido, id) do
    assert {:ok, server} = Statechart.spawn(jido, Reservation, id: id, data: %{"hold_duration" => @hold_duration})
    assert %{state: "held", status: :active} = Statechart.session(server)
    server
  end
end

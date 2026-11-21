defmodule Jido.Examples.Patterns.Compensation.Ledger do
  @spec apply_once(atom(), term(), term(), (map() -> map())) :: :applied | :duplicate
  def apply_once(ledger, invocation_id, operation, update) do
    Agent.get_and_update(ledger, fn state ->
      if MapSet.member?(state.accepted, invocation_id) do
        {:duplicate, state}
      else
        next = update.(state)

        {:applied,
         %{
           next
           | accepted: MapSet.put(next.accepted, invocation_id),
             operations: next.operations ++ [operation]
         }}
      end
    end)
  end
end

defmodule Jido.Examples.Patterns.Compensation.Reserve do
  use Jido.Action, name: "example_compensation_reserve"
  alias Jido.Examples.Patterns.Compensation.Ledger

  @impl true
  def run(%{order_id: order_id, amount: amount}, context) do
    reservation_id = "reservation:#{order_id}"

    Ledger.apply_once(context.ledger, {:reserve, order_id}, {:reserve, reservation_id}, fn state ->
      put_in(state, [:reservations, reservation_id], %{
        amount: amount,
        order_id: order_id,
        status: :reserved
      })
    end)

    {:ok, %{amount: amount, order_id: order_id, reservation_id: reservation_id}}
  end
end

defmodule Jido.Examples.Patterns.Compensation.Charge do
  use Jido.Action, name: "example_compensation_charge"

  @impl true
  def run(%{approved?: approved?, reservation: reservation}, _context) do
    {:ok,
     %{
       approved?: approved?,
       reservation_id: reservation.reservation_id,
       status: if(approved?, do: :approved, else: :declined)
     }}
  end
end

defmodule Jido.Examples.Patterns.Compensation.Release do
  use Jido.Action, name: "example_compensation_release"
  alias Jido.Examples.Patterns.Compensation.Ledger

  @impl true
  def run(%{reservation: reservation}, context) do
    reservation_id = reservation.reservation_id

    Ledger.apply_once(context.ledger, {:release, reservation_id}, {:release, reservation_id}, fn state ->
      update_in(state, [:reservations], &Map.delete(&1, reservation_id))
    end)

    {:ok, %{reservation_id: reservation_id, status: :compensated}}
  end
end

defmodule Jido.Examples.Patterns.Compensation.Confirm do
  use Jido.Action, name: "example_compensation_confirm"
  alias Jido.Examples.Patterns.Compensation.Ledger

  @impl true
  def run(%{reservation: reservation}, context) do
    reservation_id = reservation.reservation_id

    Ledger.apply_once(context.ledger, {:confirm, reservation_id}, {:confirm, reservation_id}, fn state ->
      put_in(state, [:reservations, reservation_id, :status], :confirmed)
    end)

    {:ok, %{reservation_id: reservation_id, status: :confirmed}}
  end
end

defmodule Jido.Examples.Patterns.Compensation do
  use Jido.Flow, name: "example_explicit_compensation"

  alias Jido.Examples.Patterns.Compensation.{Charge, Confirm, Release, Reserve}

  flow do
    step "reserve",
      action: Reserve,
      params: %{order_id: input(:order_id), amount: input(:amount)}

    step "charge",
      action: Charge,
      params: %{reservation: result("reserve"), approved?: input(:approved?)}

    choice "settle" do
      option "release",
        condition: result("charge", :approved?) == false,
        action: Release,
        params: %{reservation: result("reserve")}

      otherwise action: Confirm, params: %{reservation: result("reserve")}
    end

    output %{
      charge: result("charge"),
      reservation: result("reserve"),
      settlement: result("settle")
    }
  end
end

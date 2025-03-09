defmodule JidoTest.Signal.Bus.SubscriberTest do
  use JidoTest.Case, async: true
  alias Jido.Signal.Bus.Subscriber
  alias Jido.Signal.Bus.State, as: BusState

  describe "subscribe/4" do
    setup do
      # Create a basic bus state for testing
      {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)

      state = %BusState{
        name: :test_bus,
        child_supervisor: supervisor_pid
      }

      {:ok, state: state}
    end

    test "creates a non-persistent subscription", %{state: state} do
      subscription_id = "test-sub-1"
      path = "test.*"
      dispatch = {:pid, target: self()}

      result = Subscriber.subscribe(state, subscription_id, path, dispatch: dispatch)

      assert {:ok, new_state} = result
      assert BusState.has_subscription?(new_state, subscription_id)

      subscription = BusState.get_subscription(new_state, subscription_id)
      assert subscription.id == subscription_id
      assert subscription.path == path
      assert subscription.dispatch == dispatch
      assert subscription.persistent? == false
      assert subscription.persistence_pid == nil
    end

    test "creates a persistent subscription", %{state: state} do
      subscription_id = "test-sub-1"
      path = "test.*"
      client_dispatch = {:pid, target: self()}

      result =
        Subscriber.subscribe(state, subscription_id, path,
          dispatch: client_dispatch,
          persistent?: true
        )

      assert {:ok, new_state} = result
      assert BusState.has_subscription?(new_state, subscription_id)

      subscription = BusState.get_subscription(new_state, subscription_id)
      assert subscription.id == subscription_id
      assert subscription.path == path
      assert subscription.persistent? == true
      assert subscription.persistence_pid != nil
      assert Process.alive?(subscription.persistence_pid)

      # For persistent subscriptions, the dispatch target should be the persistence process
      # This is how signals get routed to the persistent subscription process first
      assert {:pid, target: _target} = subscription.dispatch

      # The persistent subscription process should be alive
      assert Process.alive?(subscription.persistence_pid)

      # Get persistent subscription state and verify it has the original client dispatch config
      persistent_sub_state = :sys.get_state(subscription.persistence_pid)
      assert persistent_sub_state.bus_subscription.dispatch == client_dispatch

      # Verify the client_pid in the persistent subscription is set to our test process
      assert persistent_sub_state.client_pid == self()
    end

    test "returns error when subscription already exists", %{state: state} do
      subscription_id = "test-sub-1"
      path = "test.*"
      dispatch = {:pid, target: self()}

      # Add the subscription first
      {:ok, state} = Subscriber.subscribe(state, subscription_id, path, dispatch: dispatch)

      # Try to add it again
      result = Subscriber.subscribe(state, subscription_id, path, dispatch: dispatch)

      assert {:error, error} = result
      assert error.type == :validation_error
      assert error.message =~ "Subscription already exists"
    end
  end

  describe "unsubscribe/3" do
    setup do
      # Create a basic bus state for testing
      {:ok, supervisor_pid} = DynamicSupervisor.start_link(strategy: :one_for_one)

      state = %BusState{
        name: :test_bus,
        child_supervisor: supervisor_pid
      }

      # Add a regular subscription
      subscription_id = "test-sub-1"
      path = "test.*"
      dispatch = {:pid, target: self()}

      {:ok, state} = Subscriber.subscribe(state, subscription_id, path, dispatch: dispatch)

      {:ok, state: state, subscription_id: subscription_id}
    end

    test "removes a subscription", %{state: state, subscription_id: subscription_id} do
      result = Subscriber.unsubscribe(state, subscription_id)

      assert {:ok, new_state} = result
      refute BusState.has_subscription?(new_state, subscription_id)
    end

    test "returns error when subscription does not exist", %{state: state} do
      result = Subscriber.unsubscribe(state, "non-existent-sub")

      assert {:error, error} = result
      assert error.type == :validation_error
      assert error.message =~ "Subscription does not exist"
    end
  end
end

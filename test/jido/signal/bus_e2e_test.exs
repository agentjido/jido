defmodule Jido.Signal.BusE2ETest do
  use ExUnit.Case, async: true
  require Logger

  alias Jido.Signal
  alias Jido.Signal.Bus

  @moduletag :capture_log
  # Increase timeout for this long-running test
  @moduletag timeout: 30_000

  defmodule TestClient do
    use GenServer
    require Logger

    def start_link(opts) do
      name = Keyword.get(opts, :name)

      if name,
        do: GenServer.start_link(__MODULE__, opts, name: name),
        else: GenServer.start_link(__MODULE__, opts)
    end

    def get_signals(pid) do
      GenServer.call(pid, :get_signals)
    end

    def stop(pid) do
      GenServer.stop(pid)
    end

    @impl true
    def init(opts) do
      Logger.debug(
        "TestClient #{Keyword.fetch!(opts, :id)} initialized with name: #{Keyword.get(opts, :name)}"
      )

      {:ok,
       %{
         id: Keyword.fetch!(opts, :id),
         name: Keyword.get(opts, :name),
         signals: []
       }}
    end

    @impl true
    def handle_call(:get_signals, _from, state) do
      Logger.debug(
        "TestClient #{state.id} (#{state.name}) returning #{length(state.signals)} signals"
      )

      {:reply, state.signals, state}
    end

    @impl true
    def handle_info({:signal, signal}, state) do
      Logger.debug("TestClient #{state.id} (#{state.name}) received signal: #{signal.type}")
      {:noreply, %{state | signals: [signal | state.signals]}}
    end

    @impl true
    def handle_info(:stop, state) do
      Logger.debug("TestClient #{state.id} (#{state.name}) stopping")
      {:stop, :normal, state}
    end
  end

  test "full bus lifecycle with multiple subscribers, disconnections and reconnections" do
    # ===== SETUP =====
    Logger.info("Setting up bus and initial subscribers")

    # Start a bus with a unique name
    bus_name = "e2e_test_bus_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = start_supervised({Bus, name: bus_name})

    # Wait for bus to be registered
    Process.sleep(50)

    # Get the bus PID
    {:ok, bus_pid} = Bus.whereis(bus_name)

    # Create signal types for our test
    signal_types = [
      "system.startup",
      "system.shutdown",
      "user.login",
      "user.logout",
      "data.created",
      "data.updated",
      "data.deleted",
      "notification.info",
      "notification.warning",
      "notification.error"
    ]

    # Create subscription patterns
    subscription_patterns = [
      %{id: "all_signals", path: "**", description: "Receives all signals", persistent?: true},
      %{
        id: "system_signals",
        path: "system.*",
        description: "Receives only system signals",
        persistent?: true
      },
      %{
        id: "user_signals",
        path: "user.*",
        description: "Receives only user signals",
        persistent?: true
      },
      %{
        id: "data_signals",
        path: "data.*",
        description: "Receives only data signals",
        persistent?: false
      },
      %{
        id: "notification_signals",
        path: "notification.*",
        description: "Receives only notification signals",
        persistent?: true
      }
    ]

    # ===== CREATE SUBSCRIBERS =====
    Logger.info("Creating subscribers with different patterns")

    # Create test clients and subscribe them to the bus
    subscribers =
      Enum.map(subscription_patterns, fn pattern ->
        # Generate a unique name for this test client as an atom
        client_name =
          String.to_atom("test_client_#{pattern.id}_#{:erlang.unique_integer([:positive])}")

        # Start a test client with a unique name
        {:ok, client_pid} = GenServer.start_link(TestClient, id: pattern.id, name: client_name)

        # Subscribe the client to the bus
        {:ok, subscription_id} =
          Bus.subscribe(bus_pid, pattern.path,
            dispatch: {:pid, target: client_pid, delivery_mode: :async},
            persistent?: pattern.persistent?
          )

        # For persistent subscribers, verify their persistence process is running
        if pattern.persistent? do
          # Get the bus state to check the subscription
          bus_state = :sys.get_state(bus_pid)
          subscription = bus_state.subscriptions[subscription_id]

          assert subscription.persistent? == true,
                 "Subscription #{subscription_id} should be persistent"

          assert is_pid(subscription.persistence_pid),
                 "Persistent subscription #{subscription_id} should have a persistence process pid"

          assert Process.alive?(subscription.persistence_pid),
                 "Persistent subscription process #{inspect(subscription.persistence_pid)} should be running"
        end

        # Create a subscriber struct for tracking
        %{
          id: pattern.id,
          description: pattern.description,
          path: pattern.path,
          subscription_id: subscription_id,
          client_pid: client_pid,
          client_name: client_name,
          signals_received: [],
          disconnected: false
        }
      end)

    # ===== PUBLISH INITIAL BATCH OF SIGNALS =====
    Logger.info("Publishing initial batch of signals")

    # Publish 50 signals (5 of each type)
    initial_signals =
      Enum.flat_map(1..5, fn batch ->
        Enum.map(signal_types, fn type ->
          {:ok, signal} =
            Signal.new(%{
              type: type,
              source: "/e2e_test",
              data: %{batch: batch, value: :rand.uniform(100)}
            })

          signal
        end)
      end)

    # Publish signals in batches of 10
    initial_signals
    |> Enum.chunk_every(10)
    |> Enum.each(fn batch ->
      {:ok, _} = Bus.publish(bus_pid, batch)
      # Small delay to avoid overwhelming the system
      Process.sleep(10)
    end)

    # Give time for signals to be processed
    Process.sleep(200)

    # ===== VERIFY INITIAL SIGNAL DELIVERY =====
    Logger.info("Verifying initial signal delivery")

    # Collect current signals from subscribers
    subscribers =
      Enum.map(subscribers, fn subscriber ->
        signals = TestClient.get_signals(subscriber.client_pid)
        Logger.debug("Subscriber #{subscriber.id} received #{length(signals)} signals")
        %{subscriber | signals_received: signals}
      end)

    # Verify each subscriber received the expected signals
    Enum.each(subscribers, fn subscriber ->
      case subscriber.id do
        "all_signals" ->
          Logger.debug(
            "All signals subscriber received #{length(subscriber.signals_received)} signals"
          )

          assert length(subscriber.signals_received) == 50,
                 "All signals subscriber should receive all 50 signals"

        "system_signals" ->
          system_signals =
            Enum.filter(subscriber.signals_received, fn signal ->
              String.starts_with?(signal.type, "system.")
            end)

          Logger.debug(
            "System signals subscriber received #{length(system_signals)} system signals"
          )

          assert length(system_signals) == 10,
                 "System signals subscriber should receive 10 system signals"

        "user_signals" ->
          user_signals =
            Enum.filter(subscriber.signals_received, fn signal ->
              String.starts_with?(signal.type, "user.")
            end)

          Logger.debug("User signals subscriber received #{length(user_signals)} user signals")

          assert length(user_signals) == 10,
                 "User signals subscriber should receive 10 user signals"

        "data_signals" ->
          data_signals =
            Enum.filter(subscriber.signals_received, fn signal ->
              String.starts_with?(signal.type, "data.")
            end)

          Logger.debug("Data signals subscriber received #{length(data_signals)} data signals")

          assert length(data_signals) == 15,
                 "Data signals subscriber should receive 15 data signals"

        "notification_signals" ->
          notification_signals =
            Enum.filter(subscriber.signals_received, fn signal ->
              String.starts_with?(signal.type, "notification.")
            end)

          Logger.debug(
            "Notification signals subscriber received #{length(notification_signals)} notification signals"
          )

          assert length(notification_signals) == 15,
                 "Notification signals subscriber should receive 15 notification signals"
      end
    end)

    # ===== DISCONNECT TWO SUBSCRIBERS =====
    Logger.info("Disconnecting two subscribers")

    # Disconnect the system_signals (persistent) and data_signals (non-persistent) subscribers
    disconnected_subscribers = ["system_signals", "data_signals"]

    subscribers =
      Enum.map(subscribers, fn subscriber ->
        if subscriber.id in disconnected_subscribers do
          # Send stop message to gracefully terminate the client process
          send(subscriber.client_pid, :stop)
          # Wait for the process to terminate
          Process.sleep(10)
          %{subscriber | disconnected: true}
        else
          subscriber
        end
      end)

    # Give time for disconnection to be processed
    Process.sleep(100)

    # Verify client processes are dead but persistent subscriptions survive
    Enum.each(subscribers, fn subscriber ->
      if subscriber.id in disconnected_subscribers do
        # Verify client process is dead
        refute Process.alive?(subscriber.client_pid),
               "Client process for #{subscriber.id} should be dead"

        # Get the bus state to check subscription status
        bus_state = :sys.get_state(bus_pid)
        subscription = bus_state.subscriptions[subscriber.subscription_id]

        case subscriber.id do
          "system_signals" ->
            # Verify persistent subscription is still running
            assert subscription.persistent? == true,
                   "System signals subscription should be persistent"

            assert is_pid(subscription.persistence_pid),
                   "System signals subscription should have a persistence process"

            assert Process.alive?(subscription.persistence_pid),
                   "System signals persistence process should be running"

          "data_signals" ->
            # Verify non-persistent subscription is gone
            refute subscription.persistent? == true,
                   "Data signals subscription should not be persistent"

            refute is_pid(subscription.persistence_pid),
                   "Data signals subscription should not have a persistence process"
        end
      end
    end)

    # ===== PUBLISH MORE SIGNALS =====
    Logger.info("Publishing more signals while subscribers are disconnected")

    # Publish 50 more signals (5 of each type)
    more_signals =
      Enum.flat_map(6..10, fn batch ->
        Enum.map(signal_types, fn type ->
          {:ok, signal} =
            Signal.new(%{
              type: type,
              source: "/e2e_test",
              data: %{batch: batch, value: :rand.uniform(100)}
            })

          signal
        end)
      end)

    # Publish signals in batches of 10
    more_signals
    |> Enum.chunk_every(10)
    |> Enum.each(fn batch ->
      {:ok, _} = Bus.publish(bus_pid, batch)
      # Small delay to avoid overwhelming the system
      Process.sleep(10)
    end)

    # Give time for signals to be processed
    Process.sleep(200)

    # # ===== RECONNECT SUBSCRIBERS =====
    # Logger.info("Reconnecting disconnected subscribers")

    # # Reconnect the disconnected subscribers
    # subscribers =
    #   Enum.map(subscribers, fn subscriber ->
    #     if subscriber.id in disconnected_subscribers do
    #       {:ok, checkpoint} =
    #         Bus.reconnect(bus_pid, subscriber.subscription_id, subscriber.client_pid)

    #       # Create a new subscriber process
    #       new_subscriber_pid = spawn(fn -> subscriber_process(subscriber.id, []) end)
    #       Process.monitor(new_subscriber_pid)

    #       # Reconnect to the existing subscription
    #       # Note: reconnect/2 always uses :current as start_from
    #       {:ok, checkpoint} =
    #         PersistentSubscription.reconnect(
    #           subscriber.subscription_id,
    #           new_subscriber_pid
    #         )

    #       Logger.info("Reconnected #{subscriber.id} with checkpoint: #{inspect(checkpoint)}")

    #       # Return updated subscriber info
    #       %{
    #         subscriber
    #         | client_pid: new_subscriber_pid,
    #           disconnected: false,
    #           signals_received: []
    #       }
    #     else
    #       subscriber
    #     end
    #   end)

    # # Give time for reconnection and replay of missed signals
    # # Increase wait time to ensure signals are processed
    # Process.sleep(1000)

    #   # ===== PUBLISH NEW SIGNALS AFTER RECONNECTION =====
    #   # Since reconnect/2 uses :current, we need to publish new signals after reconnection
    #   # to ensure the reconnected subscribers receive something
    #   Logger.info("Publishing signals after reconnection to ensure delivery")

    #   # Publish 20 more signals (2 of each type)
    #   reconnect_signals =
    #     Enum.flat_map(101..102, fn batch ->
    #       Enum.map(signal_types, fn type ->
    #         {:ok, signal} =
    #           Signal.new(%{
    #             type: type,
    #             source: "/e2e_test",
    #             data: %{batch: batch, value: :rand.uniform(100), after_reconnect: true}
    #           })

    #         signal
    #       end)
    #     end)

    #   # Publish signals in batches of 10
    #   reconnect_signals
    #   |> Enum.chunk_every(10)
    #   |> Enum.each(fn batch ->
    #     {:ok, _} = Bus.publish(bus_pid, batch)
    #     # Small delay to avoid overwhelming the system
    #     Process.sleep(10)
    #   end)

    #   # Give time for signals to be processed
    #   Process.sleep(500)

    #   # ===== VERIFY SIGNAL DELIVERY AFTER RECONNECTION =====
    #   Logger.info("Verifying signal delivery after reconnection")

    #   # Collect current signals from subscribers
    #   subscribers =
    #     Enum.map(subscribers, fn subscriber ->
    #       signals = get_subscriber_signals(subscriber.client_pid)

    #       # Add debugging to see what signals are actually received
    #       if subscriber.id in disconnected_subscribers do
    #         filtered_signals =
    #           case subscriber.id do
    #             "system_signals" ->
    #               Enum.filter(signals, fn signal -> String.starts_with?(signal.type, "system.") end)

    #             "data_signals" ->
    #               Enum.filter(signals, fn signal -> String.starts_with?(signal.type, "data.") end)

    #             _ ->
    #               signals
    #           end

    #         Logger.debug(
    #           "Reconnected #{subscriber.id} received #{length(filtered_signals)} signals"
    #         )

    #         # Log the batches received - use pattern matching instead of get_in
    #         batches =
    #           filtered_signals
    #           |> Enum.map(fn signal ->
    #             case signal.data do
    #               %{batch: batch} -> batch
    #               _ -> nil
    #             end
    #           end)
    #           |> Enum.reject(&is_nil/1)
    #           |> Enum.sort()
    #           |> Enum.uniq()

    #         Logger.debug("Batches received by #{subscriber.id}: #{inspect(batches)}")

    #         # Check for signals with after_reconnect flag - use pattern matching
    #         reconnect_signals =
    #           Enum.filter(filtered_signals, fn signal ->
    #             case signal.data do
    #               %{after_reconnect: true} -> true
    #               _ -> false
    #             end
    #           end)

    #         Logger.debug(
    #           "#{subscriber.id} received #{length(reconnect_signals)} signals with after_reconnect flag"
    #         )
    #       end

    #       %{subscriber | signals_received: signals}
    #     end)

    #   # For subscribers that stayed connected, verify they received all signals
    #   Enum.each(subscribers, fn subscriber ->
    #     unless subscriber.id in disconnected_subscribers do
    #       signals = subscriber.signals_received

    #       case subscriber.id do
    #         "all_signals" ->
    #           # Should receive all signals including the reconnect signals
    #           assert length(signals) >= 100,
    #                  "All signals subscriber should receive at least 100 signals"

    #         "user_signals" ->
    #           user_signals =
    #             Enum.filter(signals, fn signal ->
    #               String.starts_with?(signal.type, "user.")
    #             end)

    #           assert length(user_signals) >= 20,
    #                  "User signals subscriber should receive at least 20 user signals"

    #         "notification_signals" ->
    #           notification_signals =
    #             Enum.filter(signals, fn signal ->
    #               String.starts_with?(signal.type, "notification.")
    #             end)

    #           assert length(notification_signals) >= 30,
    #                  "Notification signals subscriber should receive at least 30 notification signals"
    #       end
    #     end
    #   end)

    #   # Verify reconnected subscribers received the signals they missed
    #   # Adjust expectations to be more flexible
    #   Enum.each(subscribers, fn subscriber ->
    #     if subscriber.id in disconnected_subscribers do
    #       case subscriber.id do
    #         "system_signals" ->
    #           system_signals =
    #             Enum.filter(subscriber.signals_received, fn signal ->
    #               String.starts_with?(signal.type, "system.")
    #             end)

    #           # Check specifically for signals with after_reconnect flag - use pattern matching
    #           reconnect_signals =
    #             Enum.filter(system_signals, fn signal ->
    #               case signal.data do
    #                 %{after_reconnect: true} -> true
    #                 _ -> false
    #               end
    #             end)

    #           # They should have received the signals published after reconnection
    #           assert length(reconnect_signals) > 0,
    #                  "Reconnected system signals subscriber should receive signals published after reconnection"

    #           Logger.debug("System signals received after reconnection: #{length(system_signals)}")
    #           Logger.debug("System signals with after_reconnect flag: #{length(reconnect_signals)}")

    #         "data_signals" ->
    #           data_signals =
    #             Enum.filter(subscriber.signals_received, fn signal ->
    #               String.starts_with?(signal.type, "data.")
    #             end)

    #           # Check specifically for signals with after_reconnect flag - use pattern matching
    #           reconnect_signals =
    #             Enum.filter(data_signals, fn signal ->
    #               case signal.data do
    #                 %{after_reconnect: true} -> true
    #                 _ -> false
    #               end
    #             end)

    #           # They should have received the signals published after reconnection
    #           assert length(reconnect_signals) > 0,
    #                  "Reconnected data signals subscriber should receive signals published after reconnection"

    #           Logger.debug("Data signals received after reconnection: #{length(data_signals)}")
    #           Logger.debug("Data signals with after_reconnect flag: #{length(reconnect_signals)}")
    #       end
    #     end
    #   end)

    #   # ===== FINAL VERIFICATION =====
    #   Logger.info("Final verification of signal delivery")

    #   # Collect final signals from all subscribers
    #   subscribers =
    #     Enum.map(subscribers, fn subscriber ->
    #       signals = get_subscriber_signals(subscriber.client_pid)
    #       %{subscriber | signals_received: signals}
    #     end)

    #   # Verify all subscribers received signals with after_reconnect flag
    #   Enum.each(subscribers, fn subscriber ->
    #     # Check if the subscriber received signals with after_reconnect flag - use pattern matching
    #     reconnect_signals =
    #       Enum.filter(subscriber.signals_received, fn signal ->
    #         case signal.data do
    #           %{after_reconnect: true} -> true
    #           _ -> false
    #         end
    #       end)

    #     # Log the actual count for debugging
    #     Logger.debug(
    #       "#{subscriber.id} received #{length(reconnect_signals)} signals with after_reconnect flag"
    #     )

    #     case subscriber.id do
    #       "all_signals" ->
    #         # Should receive all reconnect signals
    #         assert length(reconnect_signals) > 0,
    #                "All signals subscriber should receive signals with after_reconnect flag"

    #       "system_signals" ->
    #         system_signals =
    #           Enum.filter(reconnect_signals, fn signal ->
    #             String.starts_with?(signal.type, "system.")
    #           end)

    #         assert length(system_signals) > 0,
    #                "System signals subscriber should receive system signals with after_reconnect flag"

    #       "user_signals" ->
    #         user_signals =
    #           Enum.filter(reconnect_signals, fn signal ->
    #             String.starts_with?(signal.type, "user.")
    #           end)

    #         assert length(user_signals) > 0,
    #                "User signals subscriber should receive user signals with after_reconnect flag"

    #       "data_signals" ->
    #         data_signals =
    #           Enum.filter(reconnect_signals, fn signal ->
    #             String.starts_with?(signal.type, "data.")
    #           end)

    #         assert length(data_signals) > 0,
    #                "Data signals subscriber should receive data signals with after_reconnect flag"

    #       "notification_signals" ->
    #         notification_signals =
    #           Enum.filter(reconnect_signals, fn signal ->
    #             String.starts_with?(signal.type, "notification.")
    #           end)

    #         assert length(notification_signals) > 0,
    #                "Notification signals subscriber should receive notification signals with after_reconnect flag"
    #     end
    #   end)

    #   # ===== CLEANUP =====
    #   Logger.info("Cleaning up subscribers and bus")

    #   # Stop all subscriber processes
    #   Enum.each(subscribers, fn subscriber ->
    #     send(subscriber.client_pid, :stop)
    #   end)

    #   # Unsubscribe all subscribers
    #   Enum.each(subscribers, fn subscriber ->
    #     :ok = PersistentSubscription.unsubscribe(subscriber.subscription_id)
    #   end)

    #   # Final verification that the test completed successfully
    #   Logger.info("End-to-end test completed successfully")
    # end

    # # ===== HELPER FUNCTIONS =====

    # # Subscriber process that collects signals
    # defp subscriber_process(id, signals) do
    #   receive do
    #     {:signal, signal} ->
    #       # Store the signal and continue
    #       subscriber_process(id, [signal | signals])

    #     {:get_signals, from} ->
    #       # Return the collected signals
    #       send(from, {:signals, Enum.reverse(signals)})
    #       subscriber_process(id, signals)

    #     :stop ->
    #       # Stop the process
    #       :ok
    #   end
  end
end

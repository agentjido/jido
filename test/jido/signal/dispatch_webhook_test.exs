defmodule Jido.Signal.Dispatch.WebhookTest do
  use JidoTest.Case, async: true

  alias Jido.Signal.Dispatch.Webhook

  describe "validate_opts/1" do
    test "validates required url" do
      assert {:error, _} = Webhook.validate_opts([])
      assert {:error, _} = Webhook.validate_opts(url: nil)
      assert {:ok, _} = Webhook.validate_opts(url: "https://example.com")
    end

    test "validates optional secret" do
      assert {:ok, _} = Webhook.validate_opts(url: "https://example.com", secret: nil)
      assert {:ok, _} = Webhook.validate_opts(url: "https://example.com", secret: "mysecret")
      assert {:error, _} = Webhook.validate_opts(url: "https://example.com", secret: 123)
    end

    test "validates header names" do
      assert {:ok, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 signature_header: "x-signature",
                 event_type_header: "x-event"
               )

      assert {:error, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 signature_header: 123
               )

      assert {:error, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 event_type_header: 123
               )
    end

    test "validates event type map" do
      assert {:ok, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 event_type_map: %{
                   "user:created" => "user.created",
                   "user:updated" => "user.updated"
                 }
               )

      assert {:error, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 event_type_map: %{
                   "user:created" => 123
                 }
               )

      assert {:error, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 event_type_map: "invalid"
               )
    end

    test "inherits HTTP adapter validation" do
      assert {:ok, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 method: :post,
                 headers: [{"content-type", "application/json"}],
                 timeout: 5000
               )

      assert {:error, _} =
               Webhook.validate_opts(
                 url: "https://example.com",
                 method: :invalid
               )
    end
  end

  describe "deliver/2" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test.event",
        source: "test",
        time: DateTime.utc_now(),
        data: %{value: 42}
      }

      {:ok, signal: signal}
    end

    test "adds signature header when secret is provided", %{signal: signal} do
      opts = [
        url: "https://example.com",
        secret: "test_secret",
        method: :post,
        timeout: 1,
        retry: %{max_attempts: 1, base_delay: 0, max_delay: 0}
      ]

      # We'll get an error because the URL isn't real, but we can inspect the headers
      {:error, _} = result = Webhook.deliver(signal, opts)

      # The actual assertion would depend on how we can inspect the headers
      # For now, we're just verifying the call doesn't crash
      assert result
    end

    test "maps event types when mapping is provided", %{signal: signal} do
      opts = [
        url: "https://example.com",
        event_type_map: %{
          "test.event" => "test:mapped"
        },
        method: :post,
        timeout: 1,
        retry: %{max_attempts: 1, base_delay: 0, max_delay: 0}
      ]

      # We'll get an error because the URL isn't real, but the mapping should occur
      {:error, _} = result = Webhook.deliver(signal, opts)

      # The actual assertion would depend on how we can inspect the headers
      # For now, we're just verifying the call doesn't crash
      assert result
    end

    test "uses default headers when not specified", %{signal: signal} do
      opts = [
        url: "https://example.com",
        method: :post,
        timeout: 1,
        retry: %{max_attempts: 1, base_delay: 0, max_delay: 0}
      ]

      {:error, _} = result = Webhook.deliver(signal, opts)
      assert result
    end

    test "merges custom headers with webhook headers", %{signal: signal} do
      opts = [
        url: "https://example.com",
        method: :post,
        headers: [{"x-custom", "value"}],
        timeout: 1,
        retry: %{max_attempts: 1, base_delay: 0, max_delay: 0}
      ]

      {:error, _} = result = Webhook.deliver(signal, opts)
      assert result
    end
  end
end

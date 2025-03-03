defmodule Jido.Signal.Dispatch.HttpTest do
  use JidoTest.Case, async: true

  alias Jido.Signal.Dispatch.Http

  # These tests could be better ...

  describe "validate_opts/1" do
    test "validates required url" do
      assert {:error, _} = Http.validate_opts([])
      assert {:error, _} = Http.validate_opts(url: nil)
      assert {:ok, _} = Http.validate_opts(url: "https://example.com")
    end

    test "validates url format" do
      assert {:error, _} = Http.validate_opts(url: "not a url")
      assert {:error, _} = Http.validate_opts(url: "ftp://example.com")
      assert {:ok, _} = Http.validate_opts(url: "http://example.com")
      assert {:ok, _} = Http.validate_opts(url: "https://example.com")
    end

    test "validates method" do
      assert {:ok, _} = Http.validate_opts(url: "https://example.com")
      assert {:ok, _} = Http.validate_opts(url: "https://example.com", method: :post)
      assert {:ok, _} = Http.validate_opts(url: "https://example.com", method: :put)
      assert {:ok, _} = Http.validate_opts(url: "https://example.com", method: :patch)
      assert {:error, _} = Http.validate_opts(url: "https://example.com", method: :get)
      assert {:error, _} = Http.validate_opts(url: "https://example.com", method: :invalid)
    end

    test "validates headers" do
      assert {:ok, _} = Http.validate_opts(url: "https://example.com", headers: [])

      assert {:ok, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 headers: [{"content-type", "application/json"}]
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 headers: [{1, 2}]
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 headers: "invalid"
               )
    end

    test "validates timeout" do
      assert {:ok, _} = Http.validate_opts(url: "https://example.com", timeout: 5000)
      assert {:error, _} = Http.validate_opts(url: "https://example.com", timeout: 0)
      assert {:error, _} = Http.validate_opts(url: "https://example.com", timeout: -1)
      assert {:error, _} = Http.validate_opts(url: "https://example.com", timeout: "invalid")
    end

    test "validates retry configuration" do
      assert {:ok, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 retry: %{
                   max_attempts: 3,
                   base_delay: 1000,
                   max_delay: 5000
                 }
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 retry: %{
                   max_attempts: 0,
                   base_delay: 1000,
                   max_delay: 5000
                 }
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 retry: %{
                   max_attempts: 3,
                   base_delay: -1,
                   max_delay: 5000
                 }
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 retry: %{
                   max_attempts: 3,
                   base_delay: 1000,
                   max_delay: 0
                 }
               )

      assert {:error, _} =
               Http.validate_opts(
                 url: "https://example.com",
                 retry: "invalid"
               )
    end
  end

  describe "deliver/2" do
    setup do
      signal = %Jido.Signal{
        id: "test_signal",
        type: "test",
        source: "test",
        time: DateTime.utc_now(),
        data: %{value: 42}
      }

      {:ok, signal: signal}
    end

    # Note: These tests require a mock HTTP server or careful mocking of :httpc
    # For now, we'll just test the basic error cases

    test "returns error for invalid URL", %{signal: signal} do
      opts = [
        url: "not-a-url",
        method: :post,
        headers: [],
        timeout: 5000,
        retry: %{
          max_attempts: 1,
          base_delay: 0,
          max_delay: 0
        }
      ]

      assert {:error, _} = Http.deliver(signal, opts)
    end

    test "handles timeout", %{signal: signal} do
      opts = [
        # This should timeout quickly
        url: "http://localhost:1",
        method: :post,
        headers: [],
        timeout: 1,
        retry: %{
          max_attempts: 1,
          base_delay: 0,
          max_delay: 0
        }
      ]

      assert {:error, :timeout} = Http.deliver(signal, opts)
    end

    test "retries on failure", %{signal: signal} do
      opts = [
        # This will fail
        url: "http://localhost:1",
        method: :post,
        headers: [],
        timeout: 1,
        retry: %{
          max_attempts: 3,
          base_delay: 1,
          max_delay: 5
        }
      ]

      start_time = System.monotonic_time(:millisecond)
      assert {:error, _} = Http.deliver(signal, opts)
      end_time = System.monotonic_time(:millisecond)

      # Should have attempted 3 times with exponential backoff
      assert end_time - start_time >= 3
    end
  end
end

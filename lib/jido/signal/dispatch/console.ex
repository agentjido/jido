defmodule Jido.Signal.Dispatch.ConsoleAdapter do
  @moduledoc """
  An adapter for dispatching signals directly to the console output (stdout).

  This adapter implements the `Jido.Signal.Dispatch.Adapter` behaviour and provides
  functionality to print signals in a human-readable format to the console. It's
  particularly useful for:

  * Interactive development and debugging in IEx sessions
  * Local development and testing
  * Command-line tools and scripts
  * Direct observation of signal flow

  ## Output Format

  The adapter prints signals in a structured, easy-to-read format:

  ```
  [2024-03-21T10:15:30Z] SIGNAL DISPATCHED
  id=signal_id_here
  type=signal_type_here
  source=signal_source_here
  metadata={...}
  data={...}
  ```

  Features of the output:
  * ISO 8601 timestamp in UTC
  * Clear section headers
  * Pretty-printed metadata and data
  * Consistent formatting for easy parsing

  ## Configuration

  This adapter requires no configuration options. Any provided options will be ignored.

  ## Examples

      # Basic usage
      config = {:console, []}

      # Options are ignored but allowed
      config = {:console, [
        any_option: :is_ignored
      ]}

  ## Use Cases

  * Development and debugging
  * Local testing and verification
  * Signal flow monitoring
  * Educational purposes and demonstrations
  * Command-line tools

  ## Notes

  * Output is always sent to stdout
  * Data structures are pretty-printed for readability
  * Timestamps are always in UTC
  * No configuration options are required or used
  """

  @behaviour Jido.Signal.Dispatch.Adapter

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Validates the console adapter configuration options.

  This adapter accepts any options but doesn't use them. All options are
  considered valid.

  ## Parameters

  * `opts` - Keyword list of options (ignored)

  ## Returns

  * `{:ok, opts}` - Always returns ok with the unchanged options
  """
  @spec validate_opts(Keyword.t()) :: {:ok, Keyword.t()}
  def validate_opts(opts) do
    # No special validation needed for console adapter
    {:ok, opts}
  end

  @impl Jido.Signal.Dispatch.Adapter
  @doc """
  Prints a signal to the console in a human-readable format.

  ## Parameters

  * `signal` - The signal to print
  * `_opts` - Options (ignored)

  ## Returns

  * `:ok` - Signal was printed successfully

  ## Examples

      iex> signal = %Jido.Signal{
      ...>   id: "123",
      ...>   type: "user:created",
      ...>   source: "user_service",
      ...>   data: %{id: 456, name: "John"}
      ...> }
      iex> ConsoleAdapter.deliver(signal, [])
      [2024-03-21T10:15:30Z] SIGNAL DISPATCHED
      id=123
      type=user:created
      source=user_service
      metadata={}
      data=%{id: 456, name: "John"}
      :ok
  """
  @spec deliver(Jido.Signal.t(), Keyword.t()) :: :ok
  def deliver(signal, _opts) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    IO.puts("""
    [#{timestamp}] SIGNAL DISPATCHED
    id=#{signal.id}
    type=#{signal.type}
    source=#{signal.source}
    data=#{inspect(signal.data, pretty: true)}
    """)

    :ok
  end
end

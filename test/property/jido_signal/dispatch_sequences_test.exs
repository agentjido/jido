Code.require_file("../support/fuzz.exs", __DIR__)
Code.require_file("../support/jido_signal/runtime.exs", __DIR__)

defmodule Jido.Signal.Property.DispatchSequencesTest do
  use ExUnit.Case, async: false
  import StreamData
  alias Jido.{Error, Trace}
  alias Jido.Signal
  alias Jido.Signal.{Context, Dispatch}
  alias Jido.Test.Property.Fuzz
  alias Jido.Test.Property.Signal.Runtime

  defmodule Adapter do
    @behaviour Jido.Signal.Dispatch.Adapter
    def options_schema do
      Zoi.keyword(
        [
          owner: Zoi.pid() |> Zoi.required(),
          token: Zoi.any() |> Zoi.required(),
          index: Zoi.integer() |> Zoi.required(),
          mode: Zoi.enum(~w(ok error raise throw exit)) |> Zoi.required()
        ],
        unrecognized_keys: :error
      )
    end

    def deliver(_signal, opts) do
      send(opts[:owner], {opts[:token], :callback, opts[:index]})

      case opts[:mode] do
        "ok" -> :ok
        "error" -> {:error, {:failure, opts[:index]}}
        "raise" -> raise "adapter fault"
        "throw" -> throw(:adapter_fault)
        "exit" -> exit(:adapter_fault)
      end
    end
  end

  def event(event, measurements, metadata, {owner, token, emitter}) do
    if self() == emitter, do: send(owner, {token, :event, event, measurements, metadata})
  end

  for {suite, runs, bound} <- [{:property, 40, 6}, {:fuzz, 500, 20}] do
    @tag [
      {suite, true},
      fuzz_id: "dispatch_sequences",
      max_runs: runs,
      max_run_time: if(suite == :fuzz, do: 300_000, else: 10_000),
      timeout: if(suite == :fuzz, do: 900_000, else: 90_000)
    ]
    test "#{suite}: ordered dispatch results and lifecycle events", context do
      generator =
        fixed_map(%{
          "modes" => list_of(member_of(~w(ok error invalid raise throw exit)), max_length: unquote(bound)),
          "normalize" => boolean()
        })

      examples =
        for mode <- ~w(ok error invalid raise throw exit),
            normalize <- [false, true],
            do: %{"modes" => ["ok", mode, "error", "ok"], "normalize" => normalize}

      Fuzz.check(
        "dispatch_sequences",
        generator,
        Map.to_list(context) ++ [examples: examples],
        &check/1
      )
    end
  end

  defp check(%{"modes" => modes, "normalize" => normalize}) do
    token = make_ref()
    owner = self()
    handler = {__MODULE__, token}
    events = for last <- [:start, :stop, :exception], do: [:jido, :dispatch, last]
    old = Application.fetch_env(:jido, :normalize_dispatch_errors)
    Application.put_env(:jido, :normalize_dispatch_errors, normalize)
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.event/4, {owner, token, owner})

    try do
      signal =
        Signal.new!(String.duplicate("a", 1000), %{"password" => "secret-marker"}, source: "/property")

      trace = Trace.new()
      assert {:ok, signal} = Context.put_trace(signal, trace)

      configs =
        for {mode, i} <- Enum.with_index(modes),
            do: {Adapter, [owner: owner, token: token, index: i, mode: mode]}

      result =
        try do
          {:returned, Dispatch.dispatch(signal, configs)}
        catch
          kind, reason -> {kind, reason}
        end

      stop = Enum.find_index(modes, &(&1 in ~w(raise throw exit)))

      visited =
        if is_nil(stop),
          do: Enum.with_index(modes),
          else: modes |> Enum.with_index() |> Enum.take(stop + 1)

      for {mode, i} <- visited do
        unless mode == "invalid" do
          assert {^token, :event, [:jido, :dispatch, :start], %{}, metadata} = Runtime.next(token)
          assert metadata.jido_trace_id == trace.trace_id
          assert metadata.jido_span_id == trace.span_id
          assert byte_size(metadata.signal_type) <= 163
          refute inspect(metadata) =~ "secret-marker"
          assert {^token, :callback, ^i} = Runtime.next(token)
          terminal = if mode == "ok", do: :stop, else: :exception

          assert {^token, :event, [:jido, :dispatch, ^terminal], measurements, terminal_metadata} =
                   Runtime.next(token)

          assert measurements.latency_ms >= 0

          outcome =
            cond do
              mode == "ok" -> :ok
              mode == "error" -> :error
              true -> :raised
            end

          assert terminal_metadata.outcome == outcome
        end
      end

      if is_nil(stop) do
        errors = Enum.filter(visited, fn {mode, _} -> mode in ~w(error invalid) end)

        if errors == [] do
          assert result == {:returned, :ok}
        else
          assert {:returned, {:error, reasons}} = result
          assert length(reasons) == length(errors)

          Enum.zip(errors, reasons)
          |> Enum.each(fn {{mode, i}, reason} ->
            if normalize do
              if mode == "error",
                do: assert(match?(%Error.RoutingError{}, reason)),
                else: assert(match?(%Error.ValidationError{}, reason))
            else
              if mode == "error",
                do: assert(reason == {:failure, i}),
                else: assert(is_binary(reason))
            end
          end)
        end
      else
        case Enum.at(modes, stop) do
          "raise" -> assert {:error, %RuntimeError{message: "adapter fault"}} = result
          "throw" -> assert result == {:throw, :adapter_fault}
          "exit" -> assert result == {:exit, :adapter_fault}
        end
      end

      refute_received {^token, :callback, _}
      refute_received {^token, :event, _, _, _}

      assert {:error, _} =
               Dispatch.dispatch(signal, [
                 {Adapter, [owner: owner, token: token, index: 0, mode: "ok"]} | :tail
               ])

      assert {:error, _} =
               Dispatch.validate_opts({:http, [url: "https://example.test", headers: [{"x-test\n", "bad"}]]})

      refute_received {^token, :callback, _}
    after
      :telemetry.detach(handler)

      case old do
        {:ok, value} -> Application.put_env(:jido, :normalize_dispatch_errors, value)
        :error -> Application.delete_env(:jido, :normalize_dispatch_errors)
      end

      Runtime.drain(token)
    end

    ["normalization-#{normalize}", "targets-#{length(modes)}"]
  end
end

defmodule Jido.SignalActionTest do
  use ExUnit.Case, async: true

  alias Jido.{Exec, Signal, SignalAction}

  defmodule CreateThread do
    use Jido.SignalAction,
      name: "create_thread",
      description: "Create a named thread",
      vsn: 1,
      input: [
        type: "chat.thread.create",
        schema:
          Zoi.map(%{"room_id" => Zoi.string(), "name" => Zoi.string()}, unrecognized_keys: :error)
      ],
      output: [
        type: "chat.thread.created",
        schema: Zoi.map(%{"id" => Zoi.string()}, unrecognized_keys: :error)
      ]

    @impl Jido.Action
    def run(data, context) do
      if probe = context[:probe], do: send(probe, {:created, data})

      case data["name"] do
        "fail" -> {:error, :unavailable}
        "invalid" -> {:ok, %{"id" => 42}}
        _ -> {:ok, %{"id" => "thread-1"}, Map.get(context, :effects, [])}
      end
    end
  end

  defmodule Request do
    use Jido.Signal,
      type: "existing.create",
      default_source: "/caller",
      datacontenttype: "application/json",
      dataschema: "urn:chat:create:1",
      schema: Zoi.object(%{name: Zoi.string()})
  end

  defmodule Completed do
    use Jido.Signal,
      type: "existing.created",
      default_source: "/chat",
      dataschema: "urn:chat:created:1",
      schema: Zoi.object(%{id: Zoi.string()})
  end

  defmodule ExistingSignals do
    use Jido.SignalAction,
      name: "existing_signals",
      description: "Use existing Signal definitions",
      vsn: 2,
      input: Request,
      output: Completed

    @impl Jido.Action
    def run(_data, _context), do: {:ok, %{id: "thread-2"}}
  end

  defmodule ChatAction do
    defmacro __using__(opts) do
      quote do
        use Jido.SignalAction,
            unquote(opts) ++
              [
                input: Jido.SignalActionTest.Request,
                output: Zoi.object(%{id: Zoi.string()})
              ]

        @impl Jido.Action
        def run(data, %{client: client}), do: client.create_thread(data)
      end
    end
  end

  defmodule ChatCreateThread do
    use ChatAction,
      name: "chat_create_thread",
      description: "Create a thread through a domain wrapper",
      vsn: 1
  end

  defmodule Client do
    def create_thread(%{name: "General"}), do: {:ok, %{id: "thread-5"}}
  end

  defmodule DataOutput do
    use Jido.SignalAction,
      name: "data_output",
      description: "Return ordinary Action data",
      vsn: 1,
      input: [type: "data.create", schema: Zoi.object(%{name: Zoi.string()})],
      output: Zoi.object(%{id: Zoi.string()})

    @impl Jido.Action
    def run(_data, _context), do: {:ok, %{id: "thread-3"}}
  end

  defmodule NoOutput do
    use Jido.SignalAction,
      name: "no_output",
      description: "Keep the default Action output contract",
      vsn: 1,
      input: [type: "no.output", schema: Zoi.object(%{}), default_source: "/caller"]

    @impl Jido.Action
    def run(data, _context), do: {:ok, data}
  end

  defmodule ExplicitOutput do
    use Jido.SignalAction,
      name: "explicit_output",
      description: "Set an explicit result type",
      vsn: 1,
      input: [
        type: "explicit.create",
        schema: Zoi.object(%{}),
        dataschema: "urn:chat:explicit-request:1"
      ],
      output: [
        type: "explicit.created",
        schema: Zoi.object(%{id: Zoi.string()}),
        default_source: "/chat",
        dataschema: "urn:chat:explicit:1"
      ]

    @impl Jido.Action
    def run(_data, _context), do: {:ok, %{id: "thread-4"}}
  end

  test "one module is a native Action and an input Signal definition" do
    assert SignalAction.defined?(CreateThread)
    refute SignalAction.defined?(Request)
    refute SignalAction.defined?(:missing)
    refute SignalAction.defined?(%{})
    assert {:ok, %{kind: :action, target: CreateThread}} = Jido.Instruction.resolve(CreateThread)
    assert CreateThread.name() == "create_thread"
    assert CreateThread.description() == "Create a named thread"
    assert CreateThread.vsn() == 1
    assert CreateThread.type() == "chat.thread.create"
    assert CreateThread.__signal_definition__().schema == CreateThread.schema()
    assert CreateThread.__signal_action__().output.schema == CreateThread.output_schema()
    assert CreateThread.default_source() == nil
    assert CreateThread.datacontenttype() == nil
    assert CreateThread.dataschema() == nil
  end

  test "input and Action parameters use the same schema and keep string keys" do
    data = %{"room_id" => "room-1", "name" => "General"}
    assert {:ok, request} = CreateThread.new(data, source: "/caller")
    assert request.data == data
    assert {:ok, ^data} = CreateThread.validate_params(data)
    assert {:ok, %{"id" => "thread-1"}} = Exec.run(CreateThread, request.data)

    invalid = Map.put(data, "extra", true)
    assert {:error, [_ | _]} = CreateThread.new(invalid, source: "/caller")
    assert {:error, %Jido.Action.Error.InvalidInputError{}} = Exec.run(CreateThread, invalid)
  end

  test "native execution checks both schemas and keeps error and effect results" do
    data = %{"room_id" => "room-1", "name" => "invalid"}
    assert {:error, %Jido.Action.Error.InvalidInputError{}} = Exec.run(CreateThread, data)

    assert {:error, %Jido.Action.Error.ExecutionFailureError{details: %{reason: :unavailable}}} =
             Exec.run(CreateThread, %{data | "name" => "fail"})

    assert {:ok, %{"id" => "thread-1"}, [:deferred]} =
             Exec.run(CreateThread, %{"room_id" => "room-1", "name" => "General"}, %{
               effects: [:deferred]
             })
  end

  test "reply builds a fresh completion Signal with request correlation" do
    request =
      CreateThread.new!(%{"room_id" => "room-1", "name" => "General"}, source: "/caller")

    {:ok, request, trace} = Signal.Trace.ensure(request, tracestate: "vendor=value")
    {:ok, request} = Signal.put_context(request, "jidocausationid", "earlier-request")
    {:ok, data} = Exec.run(CreateThread, request.data)

    assert {:ok, reply} = CreateThread.reply(request, data, source: "/chat", id: request.id)
    assert reply.type == "chat.thread.created"
    assert reply.source == "/chat"
    assert reply.data == data
    refute reply.id == request.id
    assert Signal.Trace.get(reply) == trace
    assert Signal.get_context(reply, "jidocausationid") == request.id
    assert Signal.get_context(request, "jidocausationid") == "earlier-request"

    assert {:ok, second} = CreateThread.reply(request, data, source: "/chat")
    refute second.id == reply.id
    assert {:error, _} = CreateThread.reply(request, %{"id" => 42}, source: "/chat")
    assert {:error, _} = CreateThread.reply(request, Signal.new!("other", %{}, source: "/x"))
  end

  test "existing Signal definitions supply data and envelope contracts" do
    assert ExistingSignals.schema() == Request.schema()
    assert ExistingSignals.output_schema() == Completed.schema()
    assert ExistingSignals.vsn() == 2
    assert {:ok, request} = ExistingSignals.new(%{name: "General"})
    assert request.source == "/caller"
    assert request.datacontenttype == "application/json"
    assert request.dataschema == "urn:chat:create:1"
    assert {:ok, result} = Exec.run(ExistingSignals, request.data)
    assert {:ok, reply} = ExistingSignals.reply(request, result)
    assert reply.type == "existing.created"
    assert reply.source == "/chat"
    assert reply.dataschema == "urn:chat:created:1"
    assert Signal.Trace.get(reply)
  end

  test "a domain wrapper supplies the Signal contract and the native callback" do
    request = ChatCreateThread.new!(%{name: "General"})
    assert request.type == Request.type()
    assert ChatCreateThread.schema() == Request.schema()

    assert {:ok, %{id: "thread-5"}} =
             Exec.run(ChatCreateThread, request.data, %{client: Client})

    assert ChatCreateThread.__signal_action__().output == nil
  end

  test "constructors own type, data, and dataschema and validate the envelope" do
    assert {:ok, request} =
             ExistingSignals.new(%{name: "General"}, %{
               "type" => "other",
               "data" => %{},
               "dataschema" => "urn:other",
               "subject" => "room-1"
             })

    assert request.type == ExistingSignals.type()
    assert request.data == %{name: "General"}
    assert request.dataschema == ExistingSignals.dataschema()
    assert request.subject == "room-1"
    assert {:error, _} = CreateThread.new(%{"room_id" => "room-1", "name" => "General"})
    assert {:error, _} = ExistingSignals.new(%{name: "General"}, source: "bad source")
    assert {:error, _} = ExistingSignals.new(%{name: "General"}, :invalid)
    assert_raise Zoi.ParseError, fn -> ExistingSignals.new!(%{name: 42}) end

    assert_raise ArgumentError, fn ->
      ExistingSignals.new!(%{name: "ok"}, source: "bad source")
    end
  end

  test "a reply rejects a wrong request contract or missing output definition" do
    request = ExistingSignals.new!(%{name: "General"})

    for invalid <- [
          nil,
          %{request | type: "other"},
          %{request | dataschema: "urn:other"},
          %{request | source: "bad source"}
        ] do
      assert {:error, _} = ExistingSignals.reply(invalid, %{id: "thread-2"})
    end

    assert {:ok, %{id: "thread-3"}} = Exec.run(DataOutput, %{name: "General"})

    assert {:error, %{message: "Action has no output Signal"}} =
             DataOutput.reply(DataOutput.new!(%{name: "General"}, source: "/caller"), %{id: "x"})

    assert NoOutput.output_schema() == []
    assert {:ok, %{}} = Exec.run(NoOutput, %{})

    request = ExplicitOutput.new!(%{}, source: "/caller")
    assert request.dataschema == "urn:chat:explicit-request:1"
    assert ExplicitOutput.schema() == ExplicitOutput.__signal_definition__().schema

    assert {:ok, explicit} = ExplicitOutput.reply(request, %{id: "x"})
    assert explicit.source == "/chat"
    assert explicit.type == "explicit.created"
    assert explicit.dataschema == "urn:chat:explicit:1"
  end

  test "input and output reject tuple forms" do
    for field <- [:input, :output],
        tuple <- [~s|{"test.run", Zoi.object(%{})}|, ~s|{:completed, Zoi.object(%{})}|] do
      input = if field == :input, do: tuple, else: ~s|[type: "test.run", schema: Zoi.object(%{})]|
      output = if field == :output, do: ", output: #{tuple}", else: ""

      assert_raise CompileError, ~r/Expected Signal keyword options/, fn ->
        compile_action("""
        name: "test", description: "Reject tuple forms", vsn: 1, input: #{input}#{output}
        """)
      end
    end
  end

  test "input and output require full Signal type strings" do
    for field <- [:input, :output], type <- [":completed", ":failed", ":custom", "42"] do
      definition = "[type: #{type}, schema: Zoi.object(%{})]"

      input =
        if field == :input, do: definition, else: ~s|[type: "test.run", schema: Zoi.object(%{})]|

      output = if field == :output, do: ", output: #{definition}", else: ""

      assert_raise CompileError, ~r/expected string/, fn ->
        compile_action("""
        name: "test", description: "Test explicit Signal types", vsn: 1, input: #{input}#{output}
        """)
      end
    end
  end

  test "invalid definitions stop compilation" do
    input = ~s|[type: "test.run", schema: Zoi.object(%{})]|
    base = ~s|name: "test", description: "Test action", vsn: 1, input: #{input}|

    for {opts, message} <- [
          {~s|description: "test", vsn: 1, input: #{input}|, ~r/requires :name/},
          {~s|name: "test", vsn: 1, input: #{input}|, ~r/requires :description/},
          {~s|name: "test", description: "test", input: #{input}|, ~r/requires :vsn/},
          {~s|name: "test", description: "test", vsn: 1|, ~r/requires :input/},
          {String.replace(base, "vsn: 1", "vsn: 0"), ~r/positive integer/},
          {String.replace(base, ~s|description: "Test action"|, ~s|description: " "|),
           ~r/non-blank/},
          {base <> ", unknown: true", ~r/Unknown SignalAction options/},
          {String.replace(base, input, "MissingSignal"), ~r/Cannot load/},
          {base <> ~s|, name: "duplicate"|, ~r/unique keyword/},
          {String.replace(base, input, "42"), ~r/Expected/},
          {String.replace(base, input, "String"), ~r/Signal definition/},
          {base <> ~s|, output: [type: "result", schema: Zoi.string()]|, ~r/map-shaped/},
          {String.replace(base, "Zoi.object(%{})", "Zoi.string()"), ~r/map-shaped/},
          {String.replace(
             base,
             "Zoi.object(%{})",
             "Zoi.object(%{}) |> Zoi.refine(fn _ -> :ok end)"
           ), ~r/static module data/}
        ] do
      assert_raise CompileError, message, fn -> compile_action(opts) end
    end
  end

  defp compile_action(opts) do
    module = Module.concat(__MODULE__, "Compiled#{System.unique_integer([:positive])}")

    Code.compile_string("""
    defmodule #{inspect(module)} do
      use Jido.SignalAction, #{opts}
      def run(data, _context), do: {:ok, data}
    end
    """)
  end
end

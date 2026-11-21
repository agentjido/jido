defmodule Jido.Statechart.Conformance do
  @moduledoc false

  alias Jido.{AgentServer, Signal}
  alias Jido.Statechart
  alias Jido.Plugin.Statechart, as: Plugin
  alias Jido.Statechart.{BasicHTTP, SCXML}
  alias Jido.Statechart.Conformance.Template
  alias Jido.Statechart.SCXML.Unsupported

  @scxml "http://www.w3.org/2005/07/scxml"
  @instance __MODULE__.Instance
  @event_fields ~w(name type sendid origin origintype invokeid data)a
  @timeout 3_000
  @manual_http "418df239d9c85bc1fe04be64d1cf23b605a236975f14ed66a1c33fd40f2e059b"
  @manual_expectations %{
    # 178 observes duplicate values on the received event.
    "fb896335d018da1ef6738b1b660b18793c21204ada818f358594a97ccd6ca3c7" => %{
      status: :completed,
      state: "final",
      event: %{
        name: "event1",
        type: "external",
        data: %{"Var1" => [2, 3]},
        origin: "#_scxml_fixture",
        origintype: "scxml"
      }
    },
    # 230 compares the external event fields logged by the parent and child.
    "dceade5575837c2a2ec7948bb522a9892f344282cf2fadbdb70d60e53064cc3c" => %{
      status: :completed,
      state: "final",
      logs: :forwarded_event
    },
    # 250 checks the order of the cancelled child's exit handlers.
    "d73d7d91f8a1eea63d403ba3c7db4eec419a8f84b1d098634385cd02eb033344" => %{
      status: :completed,
      state: "final",
      logs: :child_exit
    },
    # 307 compares an unbound variable with missing data substructure.
    "633cb2a7027cfcb9c9b00e2b8c2b80c5e102dc74916b4e7deb308cb737d57f3a" => %{
      status: :completed,
      state: "final",
      logs: :late_binding
    },
    # 415 halts in the initial final state before it consumes the raised event.
    "63d8c1fa93c527486e477816395019787476a022623f3cc5bfe62cc6fec74e83" => %{
      status: :completed,
      state: "final",
      event: nil
    }
  }

  defmodule HTTPListener do
    @moduledoc false
    require Record
    Record.defrecordp(:request, :mod, Record.extract(:mod, from_lib: "inets/include/httpd.hrl"))

    def start(server) do
      root = String.to_charlist(System.tmp_dir!())

      :inets.start(:httpd,
        port: 0,
        bind_address: {127, 0, 0, 1},
        server_name: ~c"scxml-fixture",
        server_root: root,
        document_root: root,
        modules: [__MODULE__],
        fixture_agent: server
      )
    end

    def unquote(:do)(
          request(
            method: ~c"POST",
            request_uri: ~c"/",
            config_db: db,
            parsed_header: headers,
            entity_body: body
          )
        ) do
      server = :httpd_util.lookup(db, :fixture_agent)
      type = :proplists.get_value(~c"content-type", headers, ~c"")
      result = BasicHTTP.receive_post(server, IO.iodata_to_binary(body), List.to_string(type))
      response(if(result == :ok, do: 200, else: 400))
    end

    def unquote(:do)(_request), do: response(405)

    defp response(code),
      do: {:break, [response: {:response, [code: code, content_length: ~c"0"], ""}]}
  end

  def w3c(path) do
    xml = File.read!(path)
    digest = Base.encode16(:crypto.hash(:sha256, xml), case: :lower)

    if digest == @manual_http,
      do: manual_http(),
      else: template(xml, @manual_expectations[digest], Path.dirname(path))
  rescue
    error in Unsupported -> {:skip, Exception.message(error)}
    error in [File.Error, ArgumentError, KeyError] -> {:error, Exception.message(error)}
  end

  defp template(xml, manual, directory) do
    {chart, registry, http?} = Template.compile!(xml, directory, is_nil(manual))
    agent = Plugin.agent_definition("w3c_fixture", chart, registry)

    if manual do
      run_manual(agent, manual)
    else
      run(
        %{agent: agent, expect: %{status: :completed}, http: http?},
        &template_verdict/1
      )
    end
  end

  defp run_manual(agent, %{logs: check} = manual) do
    id = make_ref()

    :ok =
      :telemetry.attach(id, [:jido, :statechart, :log], &__MODULE__.capture_log/4, {self(), id})

    try do
      run(%{agent: agent, expect: Map.delete(manual, :logs)}, fn _session ->
        id
        |> receive_logs([])
        |> Enum.group_by(& &1.agent, &{&1.label, &1.value})
        |> compare_logs(check)
      end)
    after
      :telemetry.detach(id)
    end
  end

  defp run_manual(agent, expect), do: run(%{agent: agent, expect: expect})

  @doc false
  def capture_log(_event, _measurements, %{instance: @instance} = log, {caller, id}),
    do: send(caller, {id, log})

  def capture_log(_event, _measurements, _log, _context), do: :ok

  defp receive_logs(id, logs) do
    receive do
      {^id, log} -> receive_logs(id, [log | logs])
    after
      0 -> Enum.reverse(logs)
    end
  end

  defp compare_logs(logs, :child_exit) do
    case Map.to_list(logs) do
      [{"statechart-" <> _, [{nil, "Exiting sub01"}, {nil, "Exiting sub0"}]}] -> :ok
      _ -> {:fail, {:child_exit_logs, logs}}
    end
  end

  defp compare_logs(logs, :late_binding) do
    expected = [
      {"entering s0 value of Var 1 is: ", nil},
      {"no error in s0", nil},
      {"entering s1, value of non-existent substructure of Var 1 is: ", nil},
      {"No error in s1", nil}
    ]

    if logs == %{"fixture" => expected}, do: :ok, else: {:fail, {:late_binding_logs, logs}}
  end

  defp compare_logs(logs, :forwarded_event) do
    labels = Enum.map(@event_fields, &(Atom.to_string(&1) <> " is "))

    case logs do
      %{"fixture" => [{"name is ", "childToParent"}, {"type is ", "external"} | _] = original}
      when map_size(logs) == 2 ->
        if Enum.map(original, &elem(&1, 0)) == labels and
             Enum.all?(logs, fn {_, entries} -> entries == original end),
           do: :ok,
           else: {:fail, {:forwarded_event_logs, logs}}

      _ ->
        {:fail, {:forwarded_event_logs, logs}}
    end
  end

  # Fixture 513 supplies a manual POST and requires an HTTP 200 response.
  defp manual_http do
    chart =
      SCXML.compile!("""
      <scxml xmlns="#{@scxml}" version="1.0">
        <state id="waiting"/>
      </scxml>
      """)

    agent = Plugin.agent_definition("w3c_fixture", chart, %{})

    event = %{
      name: "test",
      type: "external",
      data: %{"key1" => "value1", "key2" => "value2"},
      http_method: "POST",
      http_name: "test"
    }

    run(%{
      agent: agent,
      expect: %{status: :active, event: event},
      http: true,
      http_post: "_scxmleventname=test&key1=value1&key2=value2"
    })
  end

  defp template_verdict(%{state: "pass", completion: "pass"}), do: :ok
  defp template_verdict(%{state: "fail", completion: "fail"}), do: {:fail, :fixture_reached_fail}
  defp template_verdict(session), do: {:fail, {:missing_fixture_verdict, session.state}}

  def run(test_case), do: run(test_case, fn _session -> :ok end)

  defp run(test_case, verdict) do
    test_case =
      update_in(test_case.expect, fn expect ->
        if Map.has_key?(expect, :event),
          do: Map.update!(expect, :event, &SCXML.event/1),
          else: expect
      end)

    with {:ok, root} <- Jido.start_link(name: @instance, namespace: "statechart-conformance") do
      try do
        with {:ok, server} <- Jido.start_agent(@instance, test_case.agent, id: "fixture") do
          with_http(server, test_case[:http], &run_session(server, test_case, verdict, &1))
        end
      after
        Supervisor.stop(root)
      end
    end
  end

  defp with_http(server, true, run) do
    with {:ok, listener} <- HTTPListener.start(server) do
      try do
        port = :httpd.info(listener, [:port])[:port]
        run.(http_location: "http://127.0.0.1:#{port}/")
      after
        :inets.stop(:httpd, listener)
      end
    end
  end

  defp with_http(_server, _http, run), do: run.([])

  defp run_session(server, test_case, verdict, opts) do
    with :ok <- committed(Statechart.initialize(server, Map.get(test_case, :data, %{}), opts)),
         :ok <- send_events(server, Map.get(test_case, :events, [])),
         :ok <- post_fixture(test_case[:http_post], opts[:http_location]),
         :ok <- await(server, test_case.expect),
         {:ok, _status} <- AgentServer.quiesce(server, timeout: @timeout),
         {:ok, session} <- check_session(server, test_case.expect),
         :ok <- check_agent_count(test_case) do
      verdict.(session)
    end
  end

  defp post_fixture(nil, _url), do: :ok

  defp post_fixture(body, url) do
    request = {String.to_charlist(url), [], ~c"application/x-www-form-urlencoded", body}

    case :httpc.request(:post, request, [timeout: @timeout], full_result: false) do
      {:ok, {200, _body}} -> :ok
      result -> {:fail, {:expected_http_200, result}}
    end
  end

  defp check_agent_count(%{agent_count: expected}) do
    actual = length(Jido.list_agents(@instance))
    if actual == expected, do: :ok, else: {:fail, {:agent_count, expected, actual}}
  end

  defp check_agent_count(_test_case), do: :ok

  defp send_events(server, events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      signal = Signal.new!(event, %{}, source: "/statechart/conformance")

      case committed(AgentServer.call(server, signal)) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp committed({:ok, %{status: :committed}}), do: :ok
  defp committed({:ok, %{error: reason}}), do: {:error, reason}
  defp committed({:error, _reason} = error), do: error

  defp await(server, expected) do
    await(server, expected, System.monotonic_time(:millisecond) + @timeout)
  end

  defp await(server, expected, deadline) do
    session = Statechart.session(server)
    actual = Map.take(session, Map.keys(expected))

    cond do
      actual == expected ->
        :ok

      session.status == :completed or System.monotonic_time(:millisecond) >= deadline ->
        {:fail, %{expected: expected, actual: actual}}

      true ->
        Process.sleep(10)
        await(server, expected, deadline)
    end
  end

  defp check_session(server, expected) do
    session = Statechart.session(server)
    actual = Map.take(session, Map.keys(expected))

    if actual == expected,
      do: {:ok, session},
      else: {:fail, %{expected: expected, actual: actual}}
  end
end

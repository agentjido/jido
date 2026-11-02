defmodule Jido.Flow.DSL.NestedSourceTest.Extension do
  use Jido.Flow.Extension

  defmacro branch(name, options) do
    quote do
      option unquote(name), unquote(options)
    end
  end

  defmacro fallback(options) do
    quote do
      otherwise unquote(options)
    end
  end

  defmacro local_state(schema, options) do
    quote do
      state unquote(schema), unquote(options)
    end
  end
end

defmodule Jido.Flow.DSL.NestedSourceTest do
  use ExUnit.Case, async: false

  for debug_info <- [true, false],
      form <- [:direct, :extension],
      {kind, message} <- [
        option_scope: "flow expression contains a scoped ref outside its valid scope",
        fallback_scope: "flow expression contains a scoped ref outside its valid scope",
        option_name: "Action name cannot be blank.",
        state_schema: "iterate state schema must be a Joi schema",
        fallback_parse: "unsupported Flow expression: [Date.utc_today()]; use a Flow reference, literal, map, or list",
        state_parse: "unsupported Flow expression: [Date.utc_today()]; use a Flow reference, literal, map, or list"
      ] do
    test "#{kind} keeps its #{form} declaration line with debug_info #{debug_info}" do
      {declarations, marker} = declarations(unquote(kind), unquote(form))
      {error, source} = compile_error(declarations, unquote(debug_info))

      line =
        source
        |> String.split("\n")
        |> Enum.find_index(&String.contains?(&1, marker))
        |> Kernel.+(1)

      assert error.description == unquote(message)
      assert error.file == "nested_source.ex"
      assert error.line == line
    end
  end

  test "Choice validation keeps parent and parse error precedence" do
    for {declarations, message} <- [
          {"""
           choice "" do
             option "selected", condition: item() == 1, action: Echo, params: %{}
             otherwise action: Echo, params: item()
           end
           output %{}
           """, "Action name cannot be blank."},
          {"""
           choice "route" do
             option "selected", condition: item() == 1, action: Echo, params: %{}
             otherwise action: Echo, params: Date.utc_today()
           end
           output %{}
           """, "unsupported Flow expression: Date.utc_today()"},
          {"""
           choice "route" do
             option "", condition: true, action: Echo, params: %{}
             otherwise action: Echo, params: item()
           end
           output %{}
           """, "Action name cannot be blank."}
        ] do
      {error, _source} = compile_error(declarations)
      assert String.starts_with?(error.description, message)
    end
  end

  test "fallback data keys do not identify a Choice option" do
    for {params, line} <- [{"%{}", 7}, {"item()", 6}] do
      {error, _source} =
        compile_error("""
        choice "route" do
          option "selected", condition: true, action: Echo, params: #{params}
          otherwise action: Echo, params: %{options: [item()]}
        end
        output result("route")
        """)

      assert error.description == "flow expression contains a scoped ref outside its valid scope"
      assert error.line == line
    end
  end

  test "Iterate validation keeps termination before State validation" do
    {error, _source} =
      compile_error("""
      iterate "loop" do
        state :invalid_schema, initial: %{}
        action Echo
        params %{}
        repeat 10001
      end
      output result("loop")
      """)

    assert error.description == "iterate repeat must be an integer from 1 to 10000"
    assert error.line == 5
  end

  test "an invalid Iterate update keeps the Iterate location" do
    {error, _source} =
      compile_error("""
      iterate "loop" do
        state Jido.Joi.map(), initial: %{}
        action Echo
        params %{}
        update item()
        repeat 1
      end
      output result("loop")
      """)

    assert error.description == "flow expression contains a scoped ref outside its valid scope"
    assert error.line == 5
  end

  test "invalid State initial data precedes an invalid Iterate update" do
    {error, _source} =
      compile_error("""
      iterate "loop" do
        state Jido.Joi.map(), initial: item()
        action Echo
        params %{}
        update item()
        repeat 1
      end
      output result("loop")
      """)

    assert error.description == "flow expression contains a scoped ref outside its valid scope"
    assert error.line == 6
  end

  test "quoted fields retain their parse order and the first failing field location" do
    for {declarations, marker, message} <- [
          {"""
           map "items" do
             action Echo
             params System.system_time()
             collection Date.utc_today()
           end
           output %{}
           """, "collection Date", "unsupported Flow expression: Date.utc_today()"},
          {"""
           reduce "items" do
             action Echo
             params System.system_time()
             initial Date.utc_today()
             collection []
           end
           output %{}
           """, "initial Date", "unsupported Flow expression: Date.utc_today()"},
          {"""
           choice "route" do
             option "selected", params: Date.utc_today(), condition: 1, action: Echo
             otherwise action: Echo, params: %{}
           end
           output %{}
           """, "option", "unsupported Flow condition: 1"},
          {"""
           iterate "loop" do
             state Jido.Joi.map(), initial: %{}
             action Echo
             while 1
             update System.system_time()
             params Date.utc_today()
             max_iterations 1
           end
           output %{}
           """, "params Date", "unsupported Flow expression: Date.utc_today()"},
          {"""
           iterate "loop" do
             state Jido.Joi.map(), initial: %{}
             action Echo
             while 1
             update Date.utc_today()
             params %{}
             max_iterations 1
           end
           output %{}
           """, "update Date", "unsupported Flow expression: Date.utc_today()"}
        ] do
      {error, source} = compile_error(declarations)
      assert String.starts_with?(error.description, message)
      assert Enum.at(String.split(source, "\n"), error.line - 1) =~ marker
    end
  end

  test "cycle errors select the first affected declaration in source order" do
    {error, source} =
      compile_error("""
      step "unrelated", action: Echo, params: %{}
      step "z", action: Echo, params: %{}, needs: "a"
      step "a", action: Echo, params: %{}, needs: "z"
      output %{}
      """)

    assert error.description == "flow dependency graph contains a cycle"
    assert Enum.at(String.split(source, "\n"), error.line - 1) =~ "step \"z\""
  end

  defp declarations(kind, form) do
    option = if form == :extension, do: "branch", else: "option"
    fallback = if form == :extension, do: "fallback", else: "otherwise"
    state = if form == :extension, do: "local_state", else: "state"

    case kind do
      :option_scope ->
        {"""
         choice "route" do
           #{option} "selected", condition: item() == 1, action: Echo, params: %{}
           otherwise action: Echo, params: %{}
         end
         output result("route")
         """, "#{option} \"selected\""}

      :fallback_scope ->
        {"""
         choice "route" do
           option "selected", condition: true, action: Echo, params: %{}
           #{fallback} action: Echo, params: item()
         end
         output result("route")
         """, "#{fallback} action:"}

      :option_name ->
        {"""
         choice "route" do
           #{option} "", condition: true, action: Echo, params: %{}
           otherwise action: Echo, params: %{}
         end
         output result("route")
         """, "#{option} \"\""}

      :fallback_parse ->
        {"""
         choice "route" do
           option "selected", condition: true, action: Echo, params: %{}
           #{fallback} action: Echo, params: [Date.utc_today()]
         end
         output result("route")
         """, "#{fallback} action:"}

      :state_parse ->
        {"""
         iterate "loop" do
           #{state} Jido.Joi.map(), initial: [Date.utc_today()]
           action Echo
           params %{}
           repeat 1
         end
         output result("loop")
         """, "#{state} Jido.Joi.map()"}

      :state_schema ->
        {"""
         iterate "loop" do
           #{state} :invalid_schema, initial: %{}
           action Echo
           params %{}
           repeat 1
         end
         output result("loop")
         """, "#{state} :invalid_schema"}
    end
  end

  defp compile_error(declarations, debug_info \\ true) do
    previous = Code.compiler_options()
    module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

    source = """
    defmodule #{inspect(module)} do
      use Jido.Flow, name: "nested_source", extensions: [#{inspect(__MODULE__.Extension)}]
      alias JidoActionTest.Fixtures.Actions.EchoParamsAction, as: Echo
      flow do
    #{declarations}
      end
    end
    """

    try do
      Code.compiler_options(debug_info: debug_info)

      {assert_raise(CompileError, fn -> Code.compile_string(source, "nested_source.ex") end), source}
    after
      Code.compiler_options(previous)
    end
  end
end

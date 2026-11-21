defmodule Jido.Statechart.SCXML do
  @moduledoc false
  alias Jido.Statechart.Configuration

  @scxml "http://www.w3.org/2005/07/scxml"
  @event_processor "http://www.w3.org/TR/scxml/#SCXMLEventProcessor"
  @invoke_types [
    nil,
    "scxml",
    @scxml,
    "http://www.w3.org/TR/scxml",
    "http://www.w3.org/TR/scxml/"
  ]
  @jido "urn:jido:statechart:1"
  @state_elements ["state", "parallel", "final"]
  @max_delay 4_294_967_295
  @event_fields Map.new(
                  ~w(name type sendid origin origintype invokeid data)a,
                  &{Atom.to_string(&1), &1}
                )
  @event_defaults Map.new(Map.values(@event_fields), &{&1, nil})

  defmodule Unsupported do
    @moduledoc false
    defexception [:message]
  end

  defmodule Reference do
    @moduledoc false
    defstruct [:scope, :key]
  end

  def compile!(xml), do: xml |> read!() |> chart!()
  def event_processor, do: @event_processor
  def event_fields, do: @event_fields
  def event(nil), do: nil
  def event(event) when is_map(event), do: Map.merge(@event_defaults, event)
  def invoke_types, do: @invoke_types
  def location(owner), do: "#_scxml_" <> owner

  def read!(xml) when is_binary(xml) do
    case :xmerl_sax_parser.stream(xml, [
           :skip_external_dtd,
           event_fun: &read_event/3,
           event_state: []
         ]) do
      {:ok, {:document, root}, remaining} ->
        if epilog?(remaining), do: root, else: raise(ArgumentError, "expected one XML document")

      {:statechart_doctype, _location, _reason, _tags, _stack} ->
        unsupported!("XML document types")

      {_tag, {_, _, line}, reason, _tags, _stack} ->
        raise ArgumentError, "invalid XML at line #{line}: #{reason}"
    end
  end

  def chart!({{@scxml, "scxml"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["version", "initial", "name", "datamodel", "binding"])
    unless attrs["version"] == "1.0", do: unsupported!("SCXML version #{attrs["version"]}")
    model = Map.get(attrs, "datamodel", "null")
    unless model in ["null", "jido"], do: unsupported!("data model #{model}")

    unless attrs["binding"] in [nil, "early", "late"],
      do: unsupported!("binding #{attrs["binding"]}")

    {data_models, states} =
      Enum.split_with(elements!(content), &match?({{@scxml, "datamodel"}, _, _}, &1))

    entries =
      states
      |> Enum.with_index()
      |> Enum.flat_map(fn {state, index} -> state!(state, nil, [index], model) end)

    ids = Enum.map(entries, &elem(&1, 0))
    roots = for {id, %{parent: nil}} <- entries, do: id
    initial = targets(attrs["initial"] || List.first(roots))

    if initial == [] or not Enum.all?(initial, &(&1 in ids)),
      do: raise(ArgumentError, "SCXML initial state does not exist")

    unless Enum.uniq(ids) == ids, do: raise(ArgumentError, "duplicate SCXML state id")

    {histories, entries} = Enum.split_with(entries, fn {_, state} -> state.kind == :history end)

    for {_id, state} <- entries ++ histories,
        transition <- state.transitions ++ List.wrap(state.initial),
        target <- transition.targets do
      unless target in ids do
        raise ArgumentError, "unknown SCXML transition target #{inspect(target)}"
      end
    end

    root_data = data!(model, data_models)

    data = root_data ++ Enum.flat_map(entries, fn {_id, state} -> Map.get(state, :data, []) end)

    _data_ids =
      Enum.reduce(data, MapSet.new(), fn {id, _expr}, seen ->
        if MapSet.member?(seen, id), do: raise(ArgumentError, "duplicate SCXML data id #{id}")
        MapSet.put(seen, id)
      end)

    chart = %{
      initial: initial,
      roots: roots,
      states: Map.new(entries),
      histories: Map.new(histories),
      data: data,
      root_data_keys: Enum.map(root_data, &elem(&1, 0)),
      binding: if(attrs["binding"] == "late", do: :late, else: :early),
      name: attrs["name"]
    }

    validate_target_set!(chart, initial)

    for {_id, state} <- entries ++ histories,
        transition <- state.transitions ++ List.wrap(state.initial) do
      validate_target_set!(chart, transition.targets)
    end

    for {id, state} <- entries, state.kind == :compound do
      targets = state.initial.targets

      unless targets != [] and Enum.all?(targets, &Configuration.descendant?(chart, &1, id)),
        do: raise(ArgumentError, "invalid SCXML initial target in #{inspect(id)}")
    end

    for {_id, history} <- histories, target <- history.initial.targets do
      valid =
        chart.states[target] &&
          case history.type do
            "shallow" -> chart.states[target].parent == history.parent
            "deep" -> Configuration.descendant?(chart, target, history.parent)
          end

      unless valid, do: raise(ArgumentError, "invalid SCXML history target #{inspect(target)}")
    end

    chart
  end

  def chart!(_root), do: raise(ArgumentError, "expected an SCXML root")

  defp validate_target_set!(chart, targets) do
    validate_targets!(chart, targets)

    resolved =
      Enum.flat_map(targets, fn id ->
        case chart.histories[id] do
          nil -> [id]
          history -> history.initial.targets
        end
      end)

    if resolved != targets, do: validate_targets!(chart, resolved)
  end

  defp validate_targets!(_chart, []), do: :ok

  defp validate_targets!(chart, [id | others]) do
    path = [id | Configuration.ancestors(chart, id)]

    for other <- others do
      other_path = [other | Configuration.ancestors(chart, other)]
      common = Enum.find(path, &(&1 in other_path))

      unless common not in [id, other] and match?(%{kind: :parallel}, chart.states[common]),
        do: raise(ArgumentError, "SCXML targets must be in separate parallel regions")
    end

    validate_targets!(chart, others)
  end

  defp state!({{@scxml, element} = name, attributes, content}, parent, path, model)
       when element in ["state", "parallel"] do
    allowed = if element == "state", do: ["id", "initial"], else: ["id"]
    attrs = attrs!(name, attributes, allowed)
    id = state_id!(attrs, path)

    groups =
      content
      |> elements!()
      |> Enum.with_index()
      |> Enum.group_by(fn
        {{{@scxml, type}, _, _}, _index} when type in @state_elements ->
          :states

        {{{@scxml, type}, _, _}, _index}
        when type in ["transition", "invoke", "initial", "onentry", "onexit", "datamodel"] ->
          type

        {{{@scxml, "history"}, _, _}, _index} ->
          :histories

        {{child, _, _}, _index} ->
          unsupported!("state element #{inspect(child)}")
      end)

    descendants =
      Enum.flat_map(Map.get(groups, :states, []), fn {state, index} ->
        state!(state, id, path ++ [index], model)
      end)

    children = for {child, %{parent: ^id}} <- descendants, do: child

    kind =
      case {element, children} do
        {"parallel", []} -> raise ArgumentError, "SCXML parallel must have children"
        {"parallel", _} -> :parallel
        {"state", []} -> :atomic
        {"state", _} -> :compound
      end

    state = %{
      kind: kind,
      parent: parent,
      children: children,
      initial: initial!(kind, attrs["initial"], nodes(groups, "initial"), children),
      completion: nil,
      data: data!(model, nodes(groups, "datamodel")),
      invoke: Enum.map(nodes(groups, "invoke"), &invoke!/1),
      transitions:
        Enum.map(Map.get(groups, "transition", []), fn {node, index} ->
          Map.put(transition!(node), :order, path ++ [index])
        end),
      onentry: handlers!(nodes(groups, "onentry")),
      onexit: handlers!(nodes(groups, "onexit"))
    }

    [{id, state} | descendants ++ Enum.map(nodes(groups, :histories), &history!(&1, id))]
  end

  defp state!({{@scxml, "final"} = name, attributes, content}, parent, path, _model) do
    id = name |> attrs!(attributes, ["id"]) |> state_id!(path)

    groups =
      Enum.group_by(elements!(content), fn
        {{@scxml, tag}, _, _} when tag in ["onentry", "onexit"] -> tag
        _ -> :completion
      end)

    completion =
      case Map.get(groups, :completion, []) do
        [] ->
          nil

        [{{@scxml, "donedata"}, [], children}] ->
          case elements!(children) do
            [{{@scxml, "content"}, _, _} = content] -> content!(content)
            params -> {:params, Enum.map(params, &param!/1)}
          end

        _ ->
          unsupported!("final state content")
      end

    [
      {id,
       %{
         kind: :final,
         parent: parent,
         children: [],
         initial: nil,
         completion: completion,
         invoke: nil,
         transitions: [],
         onentry: handlers!(Map.get(groups, "onentry", [])),
         onexit: handlers!(Map.get(groups, "onexit", []))
       }}
    ]
  end

  defp state!({name, _, _}, _parent, _path, _model),
    do: unsupported!("top-level element #{inspect(name)}")

  defp state_id!(%{"id" => _} = attrs, _path), do: required!(attrs, "id")
  defp state_id!(_attrs, path), do: "@state." <> Enum.join(path, ".")

  defp nodes(groups, group), do: Enum.map(Map.get(groups, group, []), &elem(&1, 0))

  defp history!({name, attributes, content}, parent) do
    attrs = attrs!(name, attributes, ["id", "type"])
    type = Map.get(attrs, "type", "shallow")
    unless type in ["shallow", "deep"], do: unsupported!("history type #{type}")

    {required!(attrs, "id"),
     %{
       kind: :history,
       type: type,
       parent: parent,
       initial: default_transition!(content, "history"),
       transitions: []
     }}
  end

  defp initial!(:compound, attribute, [], children),
    do: %{targets: targets(attribute || hd(children)), actions: []}

  defp initial!(:compound, nil, [{{@scxml, "initial"}, [], content}], _children),
    do: default_transition!(content, "initial")

  defp initial!(_kind, nil, [], _children), do: nil

  defp initial!(_kind, _attribute, _elements, _children),
    do: raise(ArgumentError, "invalid SCXML initial declaration")

  defp default_transition!(content, element) do
    case elements!(content) do
      [transition] ->
        case transition!(transition) do
          %{events: nil, guard: nil, targets: [_ | _]} = initial -> initial
          _ -> raise ArgumentError, "invalid SCXML #{element} transition"
        end

      _ ->
        raise ArgumentError, "SCXML #{element} requires one transition"
    end
  end

  defp handlers!(elements) do
    Enum.map(elements, fn {name, attrs, content} ->
      attrs!(name, attrs, [])
      Enum.map(elements!(content), &action!/1)
    end)
  end

  defp data!(_model, []), do: []

  defp data!("jido", [{{@scxml, "datamodel"} = name, attributes, children}]) do
    attrs!(name, attributes, [])

    Enum.map(elements!(children), fn
      {{@scxml, "data"} = name, attrs, content} ->
        attrs = attrs!(name, attrs, ["id", "expr", "src"])
        id = required!(attrs, "id")
        if reserved?(id), do: raise(ArgumentError, "reserved SCXML data ID #{inspect(id)}")

        expr =
          case {attrs["src"], attrs["expr"], String.trim(text!(content))} do
            {source, nil, ""} when is_binary(source) -> {:source, source}
            {nil, expr, ""} -> expression(expr)
            {nil, nil, text} -> expression(text)
            _ -> raise ArgumentError, "SCXML data requires at most one src, expr, or inline value"
          end

        {id, expr}

      {name, _, _} ->
        unsupported!("data model element #{inspect(name)}")
    end)
  end

  defp data!(_model, _elements), do: unsupported!("data model declaration")

  defp invoke!({{@scxml, "invoke"} = name, attributes, content}) do
    attrs =
      attrs!(name, attributes, [
        "id",
        "idlocation",
        "src",
        "srcexpr",
        "type",
        "typeexpr",
        "autoforward",
        "namelist"
      ])

    unless attrs["autoforward"] in [nil, "false", "true"], do: unsupported!("invoke autoforward")
    unless attrs["type"] in @invoke_types, do: unsupported!("invoke type #{attrs["type"]}")

    if attrs["id"] && attrs["idlocation"],
      do: raise(ArgumentError, "SCXML invoke requires at most one id or idlocation")

    {params, body} = Enum.split_with(elements!(content), &match?({{@scxml, "param"}, _, _}, &1))
    {finalize, body} = Enum.split_with(body, &match?({{@scxml, "finalize"}, _, _}, &1))

    if attrs["namelist"] && params != [],
      do: raise(ArgumentError, "SCXML invoke requires either namelist or param elements")

    source =
      case {value_attribute!(attrs, "src"), body} do
        {src, []} when not is_nil(src) ->
          {:registered, src}

        {nil, [{{@scxml, "content"}, [], children}]} ->
          inline_chart!(children)

        {nil, [{{@scxml, "content"}, [_ | _], _} = content]} ->
          content!(content)

        _ ->
          unsupported!("invoke source")
      end

    %{
      id: attrs["id"],
      idlocation: attrs["idlocation"],
      type: value_attribute!(attrs, "type"),
      source: source,
      forward: attrs["autoforward"] == "true",
      params: namelist(attrs["namelist"]) ++ Enum.map(params, &param!/1),
      finalize: finalize!(handlers!(finalize), attrs["namelist"], params)
    }
  end

  defp inline_chart!(children) do
    case elements!(children) do
      [{{@scxml, "scxml"}, _, _} = chart] -> {:inline, chart!(chart)}
      _ -> unsupported!("expected one inline SCXML chart")
    end
  end

  defp finalize!([], _namelist, _params), do: []

  defp finalize!([[]], namelist, params) do
    locations =
      for {_, attrs, _} <- params,
          {_, location} <- [List.keyfind(attrs, {nil, "location"}, 0)] do
        {_, name} = List.keyfind(attrs, {nil, "name"}, 0)
        {name, location}
      end

    bindings = Enum.map(targets(namelist), &{&1, &1}) ++ locations
    [[{:copy_returned, bindings}]]
  end

  defp finalize!([actions] = blocks, _namelist, _params) do
    Enum.each(actions, &validate_finalize!/1)
    blocks
  end

  defp finalize!(_blocks, _namelist, _params),
    do: raise(ArgumentError, "SCXML invoke allows one finalize element")

  defp validate_finalize!({:if, branches}),
    do: Enum.each(branches, fn {_guard, actions} -> Enum.each(actions, &validate_finalize!/1) end)

  defp validate_finalize!({:foreach, _, _, _, actions}),
    do: Enum.each(actions, &validate_finalize!/1)

  defp validate_finalize!(action) when elem(action, 0) in [:send, :raise, :action],
    do: raise(ArgumentError, "SCXML finalize cannot execute #{elem(action, 0)}")

  defp validate_finalize!(_action), do: :ok

  defp transition!({{@scxml, "transition"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["target", "event", "cond", "type"])
    events = String.split(Map.get(attrs, "event", ""))
    type = Map.get(attrs, "type", "external")
    unless type in ["internal", "external"], do: unsupported!("transition type #{type}")

    %{
      targets: targets(attrs["target"]),
      events: if(Map.has_key?(attrs, "event"), do: events, else: nil),
      guard: condition(attrs["cond"]),
      type: type,
      actions: Enum.map(elements!(content), &action!/1)
    }
  end

  defp transition!({name, _, _}), do: unsupported!("state element #{inspect(name)}")

  defp targets(nil), do: []
  defp targets(value), do: String.split(value)

  defp condition("In(" <> _ = source) do
    case Regex.run(~r/\AIn\(\s*([^\s"'()]+)\s*\)\z/, source) do
      [_, id] -> {:in_state, id}
      nil -> unsupported!("SCXML condition #{inspect(source)}")
    end
  end

  defp condition(value), do: value

  defp action!({{@scxml, "if"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["cond"])
    first = {condition(expression_source!(attrs, "cond")), []}

    {branches, _else_seen} =
      Enum.reduce(elements!(content), {[first], false}, fn
        {{@scxml, "elseif"} = name, attrs, children}, {branches, false} ->
          empty!(name, children)
          guard = name |> attrs!(attrs, ["cond"]) |> expression_source!("cond") |> condition()
          {[{guard, []} | branches], false}

        {{@scxml, "else"} = name, [], children}, {branches, false} ->
          empty!(name, children)
          {[{true, []} | branches], true}

        action, {[{guard, actions} | branches], else_seen} ->
          {[{guard, [action!(action) | actions]} | branches], else_seen}
      end)

    {:if,
     branches
     |> Enum.reverse()
     |> Enum.map(fn {guard, actions} -> {guard, Enum.reverse(actions)} end)}
  end

  defp action!({{@scxml, "raise"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["event"])
    empty!(name, content)
    {:raise, required!(attrs, "event")}
  end

  defp action!({{@scxml, "foreach"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["array", "item", "index"])
    array = expression(expression_source!(attrs, "array"))

    {:foreach, array, required!(attrs, "item"), attrs["index"], Enum.map(elements!(content), &action!/1)}
  end

  defp action!({{@scxml, "log"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["label", "expr"])
    empty!(name, content)
    {:log, attrs["label"], expression(attrs["expr"])}
  end

  defp action!({{@scxml, "send"} = name, attributes, content}) do
    attrs =
      attrs!(name, attributes, [
        "event",
        "eventexpr",
        "delay",
        "delayexpr",
        "target",
        "targetexpr",
        "type",
        "typeexpr",
        "namelist",
        "id",
        "idlocation"
      ])

    event = value_attribute!(attrs, "event")
    type = value_attribute!(attrs, "type")

    if attrs["id"] && attrs["idlocation"],
      do: raise(ArgumentError, "SCXML send requires at most one id or idlocation")

    {:send,
     %{
       event: event,
       delay: value_attribute!(attrs, "delay"),
       target: value_attribute!(attrs, "target"),
       type: type,
       id: attrs["id"],
       idlocation: attrs["idlocation"],
       payload: send_content!(elements!(content), namelist(attrs["namelist"]))
     }}
  end

  defp action!({{@scxml, "assign"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["location", "expr"])

    expr =
      case Map.fetch(attrs, "expr") do
        {:ok, source} ->
          empty!(name, content)
          expression(source)

        :error ->
          inline_chart!(content)
      end

    {:assign, required!(attrs, "location"), expr}
  end

  defp action!({{@scxml, "cancel"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["sendid", "sendidexpr"])
    empty!(name, content)
    id = value_attribute!(attrs, "sendid") || required!(attrs, "sendid")
    {:cancel, id}
  end

  defp action!({{@jido, "action"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["id", "params"])
    empty!(name, content)
    {:action, required!(attrs, "id"), attrs["params"]}
  end

  defp action!({name, _, _}), do: unsupported!("executable element #{inspect(name)}")

  defp value_attribute!(attrs, key) do
    expr_key = key <> "expr"

    case {attrs[key], attrs[expr_key]} do
      {value, nil} -> value
      {nil, expr} -> {:expression, expression(expr)}
      _ -> raise ArgumentError, "SCXML element requires at most one #{key} or #{expr_key}"
    end
  end

  defp send_content!([{{@scxml, "content"}, [], text}], []), do: {:content, text!(text)}

  defp send_content!(elements, params),
    do: {:params, params ++ Enum.map(elements, &param!/1)}

  defp content!({name, attributes, children}) do
    attrs = attrs!(name, attributes, ["expr"])

    case Map.fetch(attrs, "expr") do
      {:ok, source} ->
        empty!(name, children)
        {:expression, expression(source)}

      :error ->
        text!(children)
    end
  end

  defp namelist(raw) do
    for key <- targets(raw), do: {key, %Reference{scope: :data, key: key}}
  end

  defp param!({{@scxml, "param"} = name, attributes, content}) do
    attrs = attrs!(name, attributes, ["name", "expr", "location"])
    empty!(name, content)

    value =
      case {attrs["expr"], attrs["location"]} do
        {expr, nil} when not is_nil(expr) -> expression(expr)
        {nil, key} when is_binary(key) -> %Reference{scope: :data, key: key}
        _ -> raise ArgumentError, "SCXML param requires one expr or location"
      end

    {required!(attrs, "name"), value}
  end

  defp param!({name, _, _}), do: unsupported!("data content #{inspect(name)}")

  defp expression(%Jido.Expr.Operation{} = expression), do: expression
  defp expression(%Reference{} = reference), do: reference
  defp expression({:append, _, _} = expression), do: expression

  defp expression(name) when name in ["_sessionid", "_name", "_event", "_ioprocessors"],
    do: system_reference(name)

  defp expression(nil), do: nil

  defp expression("_event." <> fields = source) do
    [field | path] = String.split(fields, ".")

    with {:ok, key} <- Map.fetch(@event_fields, field),
         true <- Enum.all?(path, &variable?/1) do
      %Reference{scope: :event, key: if(path == [], do: key, else: [key | path])}
    else
      _error -> {:invalid_expression, source}
    end
  end

  defp expression(source) do
    case JSON.decode(source) do
      {:ok, data} ->
        data

      {:error, _reason} ->
        [root | path] = String.split(source, ".")

        if variable?(root) and Enum.all?(path, &variable?/1),
          do: %Reference{scope: :data, key: if(path == [], do: root, else: [root | path])},
          else: {:invalid_expression, source}
    end
  end

  def variable?(name), do: Regex.match?(~r/\A[\p{L}_][\p{L}\p{N}_-]*\z/u, name)

  def reserved?("_" <> _), do: true
  def reserved?(_name), do: false

  def system_reference("_sessionid"), do: %Reference{scope: :session, key: :owner}
  def system_reference("_name"), do: %Reference{scope: :session, key: :name}
  def system_reference("_event"), do: %Reference{scope: :event, key: []}
  def system_reference("_ioprocessors"), do: %Reference{scope: :ioprocessors, key: []}

  def literal!(nil), do: nil

  def literal!(source) do
    case JSON.decode(source) do
      {:ok, data} -> data
      {:error, _reason} -> unsupported!("data expression #{inspect(source)}")
    end
  end

  def duration(value) when value in [nil, "0"], do: {:ok, 0}
  def duration(value) when is_integer(value) and value in 0..@max_delay, do: {:ok, value}
  def duration("." <> _ = value), do: duration("0" <> value)

  def duration(value) when is_binary(value) do
    case Float.parse(value) do
      {number, "ms"} when number >= 0 and number <= @max_delay ->
        {:ok, round(number)}

      {number, "s"} when number >= 0 and number <= @max_delay / 1_000 ->
        {:ok, round(number * 1_000)}

      _ ->
        :error
    end
  end

  def duration(_value), do: :error

  def param_data([]), do: nil

  def param_data(params) do
    params
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn
      {name, [value]} -> {name, value}
      {name, values} -> {name, values}
    end)
  end

  defp attrs!(name, attributes, allowed) do
    Enum.reduce(attributes, %{}, fn
      {{nil, key}, value}, acc when is_binary(key) ->
        if key not in allowed, do: unsupported!("attribute #{key} on #{inspect(name)}")
        if Map.has_key?(acc, key), do: raise(ArgumentError, "duplicate SCXML attribute #{key}")
        Map.put(acc, key, value)

      {key, _}, _acc ->
        unsupported!("attribute #{inspect(key)} on #{inspect(name)}")
    end)
  end

  defp required!(attrs, key) do
    case attrs[key] do
      value when is_binary(value) and value != "" -> value
      _ -> raise ArgumentError, "missing SCXML #{key}"
    end
  end

  defp expression_source!(attrs, key) do
    # Empty expressions reach runtime evaluation so the chart can handle error.execution.
    case Map.fetch(attrs, key) do
      {:ok, source} -> source
      :error -> raise ArgumentError, "missing SCXML #{key}"
    end
  end

  defp elements!(content) do
    Enum.reject(content, fn
      text when is_binary(text) -> String.trim(text) == "" or unsupported!("unexpected text")
      _ -> false
    end)
  end

  defp text!(content) do
    unless Enum.all?(content, &is_binary/1), do: unsupported!("non-text data")
    Enum.join(content)
  end

  defp empty!(name, content) do
    unless elements!(content) == [], do: unsupported!("content inside #{inspect(name)}")
  end

  defp epilog?(""), do: true

  defp epilog?(remaining) do
    # OTP can leave comments and whitespace after a root with a separate end tag.
    match?({:ok, _, ""}, :xmerl_sax_parser.stream("<root/>" <> remaining, [:skip_external_dtd]))
  end

  defp read_event({:startElement, uri, name, {prefix, _local}, attributes}, _location, stack) do
    attributes =
      Enum.map(attributes, fn {uri, prefix, name, value} ->
        {expanded_name(uri, prefix, name), List.to_string(value)}
      end)

    [{expanded_name(uri, prefix, name), attributes, []} | stack]
  end

  defp read_event({:endElement, _, _, _}, _location, [{name, attributes, children} | stack]),
    do: append({name, attributes, Enum.reverse(children)}, stack)

  defp read_event({event, text}, _location, [_ | _] = stack)
       when event in [:characters, :ignorableWhitespace],
       do: append(List.to_string(text), stack)

  # OTP can report only the end event for a DOCTYPE with no declarations.
  defp read_event({:startDTD, _, _, _}, location, stack), do: read_event(:endDTD, location, stack)
  defp read_event(:endDTD, _location, _stack), do: throw({:statechart_doctype, ~c"DOCTYPE"})
  defp read_event(_event, _location, stack), do: stack

  defp append(child, [{name, attributes, children} | stack]),
    do: [{name, attributes, [child | children]} | stack]

  defp append(root, []), do: {:document, root}

  defp expanded_name([], [], name), do: {nil, List.to_string(name)}

  defp expanded_name([], prefix, _name),
    do: throw({:statechart_namespace, ~c"undeclared namespace prefix " ++ prefix})

  defp expanded_name(uri, _prefix, name), do: {List.to_string(uri), List.to_string(name)}

  defp unsupported!(feature), do: raise(Unsupported, message: feature)
end

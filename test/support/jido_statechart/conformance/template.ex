defmodule Jido.Statechart.Conformance.Template do
  @moduledoc false

  alias Jido.Statechart.{BasicHTTP, SCXML}
  alias Jido.Statechart.SCXML.{Reference, Unsupported}

  @scxml "http://www.w3.org/2005/07/scxml"
  @conf "http://www.w3.org/2005/scxml-conformance"
  @http_type BasicHTTP.type()
  @event_keys SCXML.event_fields()

  def compile!(xml, directory, require_verdict?) do
    root = SCXML.read!(xml)
    translated = if require_verdict?, do: translate_root(root), else: translate(root)
    chart = SCXML.chart!(translated)

    registry = %{
      data_sources: Map.new(data_sources(translated, directory)),
      invokes: invoke_sources(directory)
    }

    {chart, registry, uses_http?(root)}
  end

  defp uses_http?({_, attrs, children}) do
    {{nil, "type"}, @http_type} in attrs or Enum.any?(children, &uses_http?/1)
  end

  defp uses_http?(_text), do: false

  defp data_sources({{@scxml, "data"}, attrs, _}, directory) do
    case List.keyfind(attrs, {nil, "src"}, 0) do
      {_, "file:" <> file = source} ->
        if file not in ["", ".", ".."] and Path.basename(file) == file,
          do: [{source, Path.join(directory, file)}],
          else: []

      _ ->
        []
    end
  end

  defp data_sources({_, _, children}, directory),
    do: Enum.flat_map(children, &data_sources(&1, directory))

  defp data_sources(_text, _directory), do: []

  defp invoke_sources(directory) do
    Map.new(Path.wildcard(Path.join(directory, "test*sub*.txml")), fn path ->
      source = "file:" <> Path.basename(path, ".txml") <> ".scxml"
      chart = path |> File.read!() |> SCXML.read!() |> translate() |> SCXML.chart!()
      {source, chart}
    end)
  end

  defp translate_root({{@scxml, "scxml"}, _, children} = root) do
    markers = for {{@conf, name}, _, _} <- children, name in ["pass", "fail"], do: name

    if Enum.sort(markers) != ["fail", "pass"] do
      raise Unsupported, message: "expected one top-level W3C pass and fail marker"
    end

    translate(root)
  end

  defp translate_root(_root), do: raise(ArgumentError, "expected an SCXML test template")

  defp translate({{@conf, verdict}, [], []}) when verdict in ["pass", "fail"] do
    {{@scxml, "final"}, [{{nil, "id"}, verdict}], [{{@scxml, "donedata"}, [], [{{@scxml, "content"}, [], [verdict]}]}]}
  end

  defp translate({{@conf, "incrementID"}, [{{nil, "id"}, id}], []}) do
    key = "Var" <> id
    expression = Jido.Expr.new!(:+, [%Reference{scope: :data, key: key}, 1])
    {{@scxml, "assign"}, [{{nil, "location"}, key}, {{nil, "expr"}, expression}], []}
  end

  defp translate({{@conf, "extendArray"}, [{{nil, "id"}, id}], []}) do
    key = "Var" <> id
    expression = {:append, %Reference{scope: :data, key: key}, [4]}
    {{@scxml, "assign"}, [{{nil, "location"}, key}, {{nil, "expr"}, expression}], []}
  end

  defp translate({{@conf, tag}, attrs, []}) when tag in ["sumVars", "concatVars"] do
    %{{nil, "id1"} => first, {nil, "id2"} => second} = Map.new(attrs)
    refs = Enum.map([first, second], &%Reference{scope: :data, key: "Var" <> &1})
    operator = if tag == "sumVars", do: :+, else: :<>
    expression = Jido.Expr.new!(operator, refs)
    {{@scxml, "assign"}, [{{nil, "location"}, "Var" <> first}, {{nil, "expr"}, expression}], []}
  end

  defp translate({{@conf, "array123"}, [], []}), do: "[1,2,3]"
  defp translate({{@conf, "someInlineVal"}, [], []}), do: "123"

  defp translate({{@conf, "contentFoo"}, [], []}), do: {{@scxml, "content"}, [], ["foo"]}

  defp translate({{@conf, "sendToSender"}, [{{nil, "name"}, event}], []}) do
    {{@scxml, "send"},
     [
       {{nil, "event"}, event},
       {{nil, "targetexpr"}, "_event.origin"},
       {{nil, "typeexpr"}, "_event.origintype"}
     ], []}
  end

  defp translate({{@scxml, tag} = name, attributes, children}) do
    {name, Enum.map(attributes, &translate_attr(tag, &1)), Enum.map(children, &translate/1)}
  end

  defp translate({name, _, _}),
    do: raise(Unsupported, message: "template element #{inspect(name)}")

  defp translate(text) when is_binary(text), do: text

  defp translate_attr("scxml", {{@conf, "datamodel"}, ""}), do: {{nil, "datamodel"}, "jido"}
  defp translate_attr("transition", {{@conf, "targetpass"}, ""}), do: {{nil, "target"}, "pass"}
  defp translate_attr("transition", {{@conf, "targetfail"}, ""}), do: {{nil, "target"}, "fail"}

  # The implementation-report templates call a POST without an event name HTTP.POST.
  defp translate_attr("transition", {{nil, "event"}, "HTTP.POST"}), do: {{nil, "event"}, "POST"}

  defp translate_attr("transition", {{@conf, "messageBodyEquals"}, encoded}) do
    ref = %Reference{scope: :event, key: [:data, "body"]}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, URI.decode_www_form(encoded)])}
  end

  defp translate_attr(tag, {{@conf, "false"}, ""}) when tag in ["transition", "if", "elseif"],
    do: {{nil, "cond"}, false}

  defp translate_attr(tag, {{@conf, "true"}, ""}) when tag in ["transition", "if", "elseif"],
    do: {{nil, "cond"}, true}

  defp translate_attr(tag, {{@conf, "inState"}, id}) when tag in ["transition", "if", "elseif"],
    do: {{nil, "cond"}, {:in_state, id}}

  defp translate_attr("transition", {{@conf, "nonBoolean"}, ""}),
    do: {{nil, "cond"}, Jido.Expr.new!(:+, [1, 1])}

  defp translate_attr(tag, {{@conf, "systemVarIsBound"}, name})
       when tag in ["transition", "if", "elseif"],
       do: {{nil, "cond"}, {:bound, SCXML.system_reference(name)}}

  defp translate_attr("transition", {{@conf, "eventFieldsAreBound"}, ""}) do
    fields = Enum.map(Map.values(@event_keys), &%Reference{scope: :event, key: &1})
    {{nil, "cond"}, {:bound, fields}}
  end

  defp translate_attr("data", {{@conf, "id"}, id}), do: {{nil, "id"}, "Var" <> id}
  defp translate_attr("param", {{@conf, "name"}, id}), do: {{nil, "name"}, "Var" <> id}

  defp translate_attr("log", {{@conf, "eventRaw"}, ""}),
    do: {{nil, "expr"}, %Reference{scope: :event, key: []}}

  defp translate_attr("assign", {{@conf, "location"}, id}), do: {{nil, "location"}, "Var" <> id}

  defp translate_attr("assign", {{@conf, "systemVarLocation"}, name}),
    do: {{nil, "location"}, name}

  defp translate_attr(tag, {{@conf, "eventField"}, name}) when tag in ["assign", "log"],
    do: {{nil, "expr"}, %Reference{scope: :event, key: Map.fetch!(@event_keys, name)}}

  defp translate_attr("assign", {{@conf, "event" <> field}, ""})
       when field in ["Name", "Type", "Sendid", "Origin", "Origintype", "Invokeid"],
       do: {{nil, "expr"}, "_event." <> String.downcase(field)}

  defp translate_attr("foreach", {{@conf, key}, id}) when key in ["item", "index"],
    do: {{nil, key}, "Var" <> id}

  defp translate_attr("foreach", {{@conf, key}, id}) when key in ["arrayVar", "arrayTextVar"],
    do: {{nil, "array"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr("foreach", {{@conf, "illegalItem"}, ""}), do: {{nil, "item"}, "1 + 1"}

  defp translate_attr("data", {{@conf, "illegalArray"}, ""}),
    do: {{nil, "expr"}, JSON.encode!("not an array")}

  defp translate_attr(tag, {{@conf, "invalidLocation"}, _}) when tag in ["assign", "param"],
    do: {{nil, "location"}, "foo.bar.baz"}

  defp translate_attr("send", {{@conf, "illegalTarget"}, ""}), do: {{nil, "target"}, "baz"}

  defp translate_attr("send", {{@conf, "unreachableTarget"}, ""}),
    do: {{nil, "target"}, "#_scxml_foo"}

  defp translate_attr("send", {{@conf, "delay"}, seconds}), do: {{nil, "delay"}, seconds <> "s"}

  defp translate_attr("send", {{@conf, "delayFromVar"}, id}),
    do: {{nil, "delayexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr("send", {{@conf, key}, id}) when key in ["targetVar", "targetExpr"],
    do: {{nil, "targetexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr(tag, {{@conf, "invalidSessionID"}, ""}) when tag in ["data", "assign"],
    do: {{nil, "expr"}, JSON.encode!("#_scxml_missing")}

  defp translate_attr("send", {{@conf, "eventExpr"}, id}),
    do: {{nil, "eventexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr(tag, {{@conf, "idlocation"}, id}) when tag in ["send", "invoke"],
    do: {{nil, "idlocation"}, "Var" <> id}

  defp translate_attr("cancel", {{@conf, "sendIDExpr"}, id}),
    do: {{nil, "sendidexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr(tag, {{@conf, "typeExpr"}, id}) when tag in ["send", "invoke"],
    do: {{nil, "typeexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr("invoke", {{@conf, "srcExpr"}, id}),
    do: {{nil, "srcexpr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr("send", {{@conf, "invalidSendType"}, ""}),
    do: {{nil, "type"}, "urn:unsupported:send-type"}

  defp translate_attr("data", {{@conf, "invalidSendTypeExpr"}, ""}),
    do: {{nil, "expr"}, JSON.encode!("urn:unsupported:send-type")}

  defp translate_attr("send", {{@conf, "basicHTTPAccessURITarget"}, ""}),
    do: {{nil, "targetexpr"}, %Reference{scope: :ioprocessors, key: [@http_type, :location]}}

  defp translate_attr("transition", {{@conf, "methodIsPost"}, ""}),
    do: {{nil, "cond"}, Jido.Expr.new!(:==, [%Reference{scope: :event, key: :http_method}, "POST"])}

  defp translate_attr(tag, {{@conf, "namelist"}, ids}) when tag in ["send", "invoke"] do
    {{nil, "namelist"}, ids |> String.split() |> Enum.map_join(" ", &("Var" <> &1))}
  end

  defp translate_attr(tag, {{@conf, "invalidNamelist"}, ""}) when tag in ["send", "invoke"],
    do: {{nil, "namelist"}, "MissingVariable"}

  defp translate_attr("transition", {{@conf, "eventIdParamHasValue"}, check}) do
    [id, value] = String.split(check, " ", parts: 2)
    event_param_equals("Var" <> id, value)
  end

  defp translate_attr("transition", {{@conf, "eventvarVal"}, check}) do
    [id, value] = String.split(check, "=", parts: 2)
    event_param_equals("Var" <> id, value)
  end

  defp translate_attr("transition", {{@conf, "eventNamedParamHasValue"}, check}) do
    [name, value] = String.split(check, " ", parts: 2)
    event_param_equals(name, value)
  end

  defp translate_attr("assign", {{@conf, key}, name})
       when key in ["eventDataParamValue", "eventDataFieldValue"],
       do: {{nil, "expr"}, %Reference{scope: :event, key: [:data, name]}}

  defp translate_attr("assign", {{@conf, "eventDataNamelistValue"}, id}),
    do: {{nil, "expr"}, %Reference{scope: :event, key: [:data, "Var" <> id]}}

  defp translate_attr("log", {{@conf, "expr"}, ""}), do: {{nil, "expr"}, nil}
  defp translate_attr(_, {{@conf, "expr"}, value}), do: {{nil, "expr"}, value}
  defp translate_attr(_, {{@conf, "quoteExpr"}, value}), do: {{nil, "expr"}, JSON.encode!(value)}

  defp translate_attr(_, {{@conf, "systemVarExpr"}, name}),
    do: {{nil, "expr"}, SCXML.system_reference(name)}

  defp translate_attr(_, {{@conf, key}, id}) when key in ["varExpr", "varChildExpr"],
    do: {{nil, "expr"}, %Reference{scope: :data, key: "Var" <> id}}

  defp translate_attr("log", {{@conf, "varNonexistentStruct"}, id}),
    do: {{nil, "expr"}, "Var" <> id <> ".missing"}

  defp translate_attr(_, {{@conf, "illegalExpr"}, ""}), do: {{nil, "expr"}, "return"}

  defp translate_attr(tag, {{@conf, "scxmlEventIOLocation"}, ""})
       when tag in ["data", "assign"] do
    ref = %Reference{scope: :ioprocessors, key: [SCXML.event_processor(), :location]}
    {{nil, "expr"}, ref}
  end

  defp translate_attr("transition", {{@conf, key}, id})
       when key in ["isBound", "unboundVar", "noValue"] do
    ref = %Reference{scope: :data, key: "Var" <> id}
    operator = if key == "isBound", do: :!=, else: :==
    {{nil, "cond"}, Jido.Expr.new!(operator, [ref, nil])}
  end

  defp translate_attr("transition", {{@conf, "varPrefix"}, ids}) do
    [prefix, value] = Enum.map(String.split(ids), &%Reference{scope: :data, key: "Var" <> &1})
    {{nil, "cond"}, {:prefix, prefix, value}}
  end

  defp translate_attr("transition", {{@conf, comparison}, ids})
       when comparison in ["VarEqVar", "VarEqVarStruct"] do
    refs = Enum.map(String.split(ids), &%Reference{scope: :data, key: "Var" <> &1})
    {{nil, "cond"}, Jido.Expr.new!(:==, refs)}
  end

  defp translate_attr("transition", {{@conf, "idSystemVarVal"}, check}) do
    [id, name] = String.split(check, "=", parts: 2)
    ref = %Reference{scope: :data, key: "Var" <> id}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, SCXML.system_reference(name)])}
  end

  defp translate_attr("transition", {{@conf, "nameVarVal"}, value}),
    do: {{nil, "cond"}, Jido.Expr.new!(:==, [SCXML.system_reference("_name"), value])}

  defp translate_attr(tag, {{@conf, "compareIDVal"}, comparison})
       when tag in ["transition", "if", "elseif"] do
    [left, right] = String.split(comparison, "<", parts: 2)
    references = Enum.map([left, right], &%Reference{scope: :data, key: "Var" <> &1})
    {{nil, "cond"}, Jido.Expr.new!(:<, references)}
  end

  defp translate_attr("transition", {{@conf, key}, expression})
       when key in ["idVal", "idQuoteVal", "namelistIdVal"] do
    case Regex.run(~r/\A(\d+)=([^=].*)\z/, expression) do
      [_, id, value] ->
        ref = %Reference{scope: :data, key: "Var" <> id}
        value = if key == "idQuoteVal", do: value, else: SCXML.literal!(value)
        comparison = Jido.Expr.new!(:==, [ref, value])
        {{nil, "cond"}, comparison}

      nil ->
        raise Unsupported, message: "template condition #{inspect(expression)}"
    end
  end

  defp translate_attr("transition", {{@conf, "eventNameVal"}, name}) do
    ref = %Reference{scope: :event, key: :name}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, name])}
  end

  defp translate_attr("transition", {{@conf, "eventFieldHasNoValue"}, field}) do
    ref = %Reference{scope: :event, key: Map.fetch!(@event_keys, field)}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, nil])}
  end

  defp translate_attr("transition", {{@conf, "originTypeEq"}, name}) do
    # SCXML 1.0 C.1 uses the short processor name in the event.
    origin_type = if name == SCXML.event_processor(), do: "scxml", else: name
    ref = %Reference{scope: :event, key: :origintype}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, origin_type])}
  end

  defp translate_attr("transition", {{@conf, "eventdataVal"}, value}) do
    ref = %Reference{scope: :event, key: :data}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, String.trim(value, "'")])}
  end

  defp translate_attr("transition", {{@conf, "eventdataSomeVal"}, ""}),
    do: translate_attr("transition", {{@conf, "eventdataVal"}, "'123'"})

  defp translate_attr("transition", {{@conf, "emptyEventData"}, ""}) do
    ref = %Reference{scope: :event, key: :data}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, nil])}
  end

  defp translate_attr(_, {{nil, _}, _} = attr), do: attr

  defp translate_attr(_, {name, _}),
    do: raise(Unsupported, message: "template attribute #{inspect(name)}")

  defp event_param_equals(name, value) do
    {key, value} =
      case {name, JSON.decode(value)} do
        {"_scxmleventname", _} -> {:http_name, value}
        {name, {:ok, decoded}} -> {[:data, name], decoded}
        {name, {:error, _reason}} -> {[:data, name], value}
      end

    ref = %Reference{scope: :event, key: key}
    {{nil, "cond"}, Jido.Expr.new!(:==, [ref, value])}
  end
end

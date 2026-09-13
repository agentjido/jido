defmodule JidoTest.Authoring.Agents.Cases do
  @moduledoc false
  alias JidoTest.Authoring.Agents.Fixtures

  # Independent expected declarations and states; no test DSL or derived results.
  def spec(variant, _module) when variant in [:counter_keyword, :counter_block] do
    %{
      id: "counter",
      schema_id: "count",
      attrs: %{
        vsn: 3,
        schema: count_schema(),
        metadata: %{case: "counter"},
        routes: [
          {"counter.add", Fixtures.Add, defaults: %{amount: 1}, priority: 10},
          {"counter.*", Fixtures.Add, defaults: %{amount: 5}, priority: -1}
        ]
      },
      references: %{
        "actions/add" => {:action, Fixtures.Add},
        "atoms/amount" => {:atom, :amount},
        "atoms/case" => {:atom, :case}
      },
      initial: %{count: 0},
      override: %{count: 10},
      override_state: %{count: 10},
      invalid_state: %{count: "invalid"},
      steps: [
        {"counter.add", %{}, %{count: 1}},
        {"counter.add", %{amount: 3}, %{count: 4}},
        {"counter.other", %{}, %{count: 9}}
      ]
    }
  end

  def spec(:inline, module) do
    target = module.route_action!("inline.add")

    %{
      id: "inline",
      schema_id: "count",
      attrs: %{
        schema: count_schema(),
        metadata: %{case: "inline"},
        routes: [{"inline.add", target, defaults: %{amount: 1}}]
      },
      references: %{
        "actions/add" => {:action, target},
        "atoms/amount" => {:atom, :amount},
        "atoms/case" => {:atom, :case}
      },
      initial: %{count: 0},
      override: %{count: 10},
      override_state: %{count: 10},
      invalid_state: %{count: "invalid"},
      steps: [{"inline.add", %{}, %{count: 2}}, {"inline.add", %{amount: 3}, %{count: 8}}]
    }
  end

  def spec(:flow_plugin, _module) do
    %{
      id: "flow",
      schema_id: "count",
      attrs: %{
        vsn: 2,
        schema: count_schema(),
        metadata: %{case: "flow"},
        routes: [{"flow.add", Fixtures.AddFlow, defaults: %{amount: 2}}],
        plugins: [{Fixtures.CountTurns, [initial: 2]}]
      },
      references: %{
        "flows/add" => {:flow, Fixtures.AddFlow},
        "plugins/count-turns" => {:plugin, Fixtures.CountTurns},
        "atoms/initial" => {:atom, :initial},
        "atoms/amount" => {:atom, :amount},
        "atoms/case" => {:atom, :case}
      },
      initial: %{count: 0, turns: 2},
      override: %{count: 10},
      override_state: %{count: 10, turns: 2},
      invalid_state: %{count: "invalid"},
      steps: [
        {"flow.add", %{}, %{count: 2, turns: 3}},
        {"flow.add", %{amount: 3}, %{count: 5, turns: 4}}
      ]
    }
  end

  def spec(:required_profile, _module) do
    %{
      id: "required_profile",
      attrs: %{
        schema: Zoi.object(%{name: Zoi.string(), active: Zoi.boolean() |> Zoi.default(false)}),
        routes: [{"profile.rename", Fixtures.Rename, []}]
      },
      references: %{"actions/rename" => {:action, Fixtures.Rename}},
      initial_opts: [state: %{name: "Ada"}],
      initial: %{name: "Ada", active: false},
      override: %{name: "Grace", active: true},
      override_state: %{name: "Grace", active: true},
      invalid_state: %{name: 42},
      steps: [{"profile.rename", %{name: "Lin"}, %{name: "Lin", active: false}}]
    }
  end

  def spec(:falsy_values, _module) do
    %{
      id: "falsy_values",
      attrs: %{
        schema:
          Zoi.object(%{
            enabled: Zoi.boolean() |> Zoi.default(false),
            amount: Zoi.integer() |> Zoi.default(0),
            note: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
          }),
        routes: [
          {"config.set", Fixtures.SetConfig,
           defaults: %{enabled: true, amount: 7, note: "default"}}
        ]
      },
      references:
        Map.put(
          atoms([:enabled, :amount, :note]),
          "actions/config",
          {:action, Fixtures.SetConfig}
        ),
      initial: %{enabled: false, amount: 0, note: nil},
      override: %{enabled: true, amount: -1, note: ""},
      override_state: %{enabled: true, amount: -1, note: ""},
      invalid_state: %{enabled: "false"},
      steps: [
        {"config.set", %{}, %{enabled: true, amount: 7, note: "default"}},
        {"config.set", %{enabled: false, amount: 0, note: nil},
         %{enabled: false, amount: 0, note: nil}}
      ]
    }
  end

  def spec(:nested_profile, _module) do
    %{
      id: "nested_profile",
      attrs: %{
        schema:
          Zoi.object(%{
            profile:
              Zoi.object(%{name: Zoi.string(), tags: Zoi.array(Zoi.string())})
              |> Zoi.default(%{name: "anonymous", tags: []})
          }),
        routes: [{"nested.rename", Fixtures.RenameNested, []}]
      },
      references: %{"actions/nested" => {:action, Fixtures.RenameNested}},
      initial: %{profile: %{name: "anonymous", tags: []}},
      override: %{profile: %{name: "Ada", tags: ["admin"]}},
      override_state: %{profile: %{name: "Ada", tags: ["admin"]}},
      invalid_state: %{profile: %{name: "Ada", tags: [42]}},
      steps: [{"nested.rename", %{name: "Lin"}, %{profile: %{name: "Lin", tags: []}}}]
    }
  end

  def spec(:list_inputs, _module) do
    %{
      id: "list_inputs",
      attrs: %{
        schema: Zoi.object(%{items: Zoi.array(Zoi.string()) |> Zoi.default([])}),
        routes: [{"items.replace", Fixtures.ReplaceItems, []}]
      },
      references: %{"actions/items" => {:action, Fixtures.ReplaceItems}},
      initial: %{items: []},
      override: %{items: ["seed"]},
      override_state: %{items: ["seed"]},
      invalid_state: %{items: [42]},
      steps: [
        {"items.replace", %{items: ["a", "b"]}, %{items: ["a", "b"]}},
        {"items.replace", %{items: []}, %{items: []}}
      ]
    }
  end

  def spec(:bounded_value, _module) do
    %{
      id: "bounded_value",
      attrs: %{
        schema:
          Zoi.object(%{value: Zoi.integer() |> Zoi.min(0) |> Zoi.max(10) |> Zoi.default(0)}),
        routes: [{"value.set", Fixtures.SetValue, []}]
      },
      references: %{"actions/value" => {:action, Fixtures.SetValue}},
      initial: %{value: 0},
      override: %{value: 10},
      override_state: %{value: 10},
      invalid_state: %{value: -1},
      steps: [
        {"value.set", %{value: 10}, %{value: 10}},
        {"value.set", %{value: 11}, {:error, Jido.Error.ValidationError}},
        {"value.set", %{value: -1}, {:error, Jido.Error.ValidationError}},
        {"value.set", %{value: 0}, %{value: 0}}
      ]
    }
  end

  def spec(:static_metadata, _module) do
    %{
      id: "static_metadata",
      attrs: %{
        schema: Zoi.object(%{payload: Zoi.map() |> Zoi.default(%{})}),
        metadata: %{stamp: ~D[2026-09-13], values: {:ready, <<255>>, 1, 1.0}},
        routes: [{"metadata.inspect", Fixtures.Noop, []}]
      },
      references:
        Map.merge(atoms([:stamp, :values, :ready]), %{
          "values/day" => {:value, ~D[2026-09-13]},
          "actions/noop" => {:action, Fixtures.Noop}
        }),
      initial: %{payload: %{}},
      override: %{payload: %{"ok" => true}},
      override_state: %{payload: %{"ok" => true}},
      invalid_state: %{payload: %{pid: self()}},
      steps: [{"metadata.inspect", %{}, %{payload: %{}}}]
    }
  end

  def spec(:predicate_routes, _module) do
    matcher = Function.capture(Fixtures.Matchers, :positive?, 1)

    %{
      id: "predicate_routes",
      attrs: %{
        schema: selected_schema(),
        routes: [
          {"choice.set", Fixtures.Choose,
           match: matcher, defaults: %{label: "positive"}, priority: 100},
          {"choice.set", Fixtures.Choose, defaults: %{label: "fallback"}}
        ]
      },
      references: %{
        "actions/choose" => {:action, Fixtures.Choose},
        "atoms/label" => {:atom, :label},
        "matches/positive" => {:route_match, matcher}
      },
      initial: %{selected: "none"},
      override: %{selected: "seed"},
      override_state: %{selected: "seed"},
      invalid_state: %{selected: false},
      steps: [
        {"choice.set", %{n: 1}, %{selected: "positive"}},
        {"unknown.event", %{}, {:error, Jido.Error.RoutingError}},
        {"choice.set", %{n: 0}, %{selected: "fallback"}}
      ]
    }
  end

  def spec(:ordered_routes, _module) do
    %{
      id: "ordered_routes",
      attrs: %{
        schema: selected_schema(),
        routes: [
          {"ordered.pick", Fixtures.Choose, defaults: %{label: "first"}, priority: 5},
          {"ordered.pick", Fixtures.Choose, defaults: %{label: "second"}, priority: 5}
        ]
      },
      references: %{
        "actions/choose" => {:action, Fixtures.Choose},
        "atoms/label" => {:atom, :label}
      },
      initial: %{selected: "none"},
      override: %{selected: "seed"},
      override_state: %{selected: "seed"},
      invalid_state: %{selected: 42},
      steps: [{"ordered.pick", %{}, %{selected: "first"}}]
    }
  end

  def spec(:built_flow, _module) do
    alias Jido.Flow.{Builder, Ref}

    {:ok, flow} =
      Builder.new(name: "corpus_built_flow", schema: Zoi.object(%{value: Zoi.integer()}))
      |> Builder.step("set", Fixtures.SetTotal, %{value: Ref.input(:value)})
      |> Builder.output(Ref.result("set"))
      |> Builder.build()

    %{
      id: "built_flow",
      attrs: %{
        schema: Zoi.object(%{total: Zoi.integer() |> Zoi.default(0)}),
        routes: [{"total.set", flow, []}]
      },
      references: %{"flows/set" => {:flow, flow}},
      initial: %{total: 0},
      override: %{total: -5},
      override_state: %{total: -5},
      invalid_state: %{total: "invalid"},
      steps: [{"total.set", %{value: 12}, %{total: 12}}, {"total.set", %{value: 0}, %{total: 0}}]
    }
  end

  def spec(:ordered_plugins, _module) do
    %{
      id: "ordered_plugins",
      attrs: %{
        schema: Zoi.object(%{value: Zoi.integer() |> Zoi.default(0)}),
        routes: [{"plugins.set", Fixtures.SetValue, []}],
        plugins: [{Fixtures.FirstPlugin, []}, {Fixtures.SecondPlugin, []}]
      },
      references: %{
        "actions/value" => {:action, Fixtures.SetValue},
        "plugins/first" => {:plugin, Fixtures.FirstPlugin},
        "plugins/second" => {:plugin, Fixtures.SecondPlugin}
      },
      initial: %{value: 0, first: 0, second: 0},
      override: %{value: 5},
      override_state: %{value: 5, first: 0, second: 0},
      invalid_state: %{value: "invalid"},
      steps: [
        {"plugins.set", %{value: 2}, %{value: 2, first: 3, second: 3}},
        {"plugins.set", %{value: 5}, %{value: 5, first: 6, second: 6}}
      ]
    }
  end

  def spec(:extension_route, _module) do
    %{
      id: "extension_route",
      attrs: %{
        schema: text_schema(),
        metadata: %{extension: "route"},
        routes: [{"text.write", Fixtures.SetText, []}]
      },
      references: %{
        "actions/text" => {:action, Fixtures.SetText},
        "atoms/extension" => {:atom, :extension}
      },
      initial: %{text: ""},
      override: %{text: "seed"},
      override_state: %{text: "seed"},
      invalid_state: %{text: 42},
      steps: [{"text.write", %{text: "lowered"}, %{text: "lowered"}}]
    }
  end

  def spec(:custom_selection, _module) do
    %{
      id: "custom_selection",
      attrs: %{schema: text_schema()},
      references: %{},
      initial: %{text: ""},
      override: %{text: "seed"},
      override_state: %{text: "seed"},
      invalid_state: %{text: 42},
      steps: [
        {"custom.write", %{text: "first"}, %{text: "first"}},
        {"custom.unknown", %{}, {:error, Jido.Error.RoutingError}},
        {"custom.write", %{text: "next"}, %{text: "next"}}
      ]
    }
  end

  defp count_schema, do: Zoi.object(%{count: Zoi.integer() |> Zoi.default(0)})
  defp selected_schema, do: Zoi.object(%{selected: Zoi.string() |> Zoi.default("none")})
  defp text_schema, do: Zoi.object(%{text: Zoi.string() |> Zoi.default("")})
  defp atoms(names), do: Map.new(names, &{"atoms/#{&1}", {:atom, &1}})
end

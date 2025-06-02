defmodule Jido.Signal.RouterDefinitionTest do
  use JidoTest.Case, async: true

  alias Jido.Instruction
  alias Jido.Signal.Router
  alias Jido.Signal.Router.{Route, Validator}

  @moduletag :capture_log

  describe "normalize/1" do
    test "normalizes single Route struct" do
      route = %Route{
        path: "test.path",
        target: %Instruction{action: TestAction}
      }

      assert {:ok, [^route]} = Validator.normalize(route)
    end

    test "normalizes list of Route structs" do
      routes = [
        %Route{
          path: "test.1",
          target: %Instruction{action: TestAction1}
        },
        %Route{
          path: "test.2",
          target: %Instruction{action: TestAction2}
        }
      ]

      assert {:ok, ^routes} = Validator.normalize(routes)
    end

    test "normalizes {path, target} tuple" do
      path = "test.path"
      target = %Instruction{action: TestAction}

      assert {:ok, [%Route{path: ^path, target: ^target}]} = Validator.normalize({path, target})
    end

    test "normalizes {path, target, priority} tuple" do
      path = "test.path"
      target = %Instruction{action: TestAction}
      priority = 10

      assert {:ok,
              [
                %Route{
                  path: ^path,
                  target: ^target,
                  priority: ^priority
                }
              ]} = Validator.normalize({path, target, priority})
    end

    test "normalizes {path, match_fn, target} tuple" do
      path = "test.path"
      target = %Instruction{action: TestAction}

      match_fn = fn signal ->
        signal.path == path
      end

      assert {:ok,
              [
                %Route{
                  path: ^path,
                  target: ^target,
                  match: ^match_fn
                }
              ]} = Validator.normalize({path, match_fn, target})
    end

    test "normalizes {path, match_fn, target, priority} tuple" do
      path = "test.path"
      target = %Instruction{action: TestAction}
      priority = 10

      match_fn = fn signal ->
        signal.path == path
      end

      assert {:ok,
              [
                %Route{
                  path: ^path,
                  target: ^target,
                  match: ^match_fn,
                  priority: ^priority
                }
              ]} = Validator.normalize({path, match_fn, target, priority})
    end

    test "normalizes {path, {adapter, opts}} tuple" do
      path = "test.path"
      adapter = :noop
      opts = [key: "value"]

      assert {:ok,
              [
                %Route{
                  path: ^path,
                  target: {^adapter, ^opts}
                }
              ]} = Validator.normalize({path, {adapter, opts}})
    end

    test "normalizes {path, [{adapter, opts}, ...]} tuple with multiple dispatch configs" do
      path = "test.path"
      test_pid = self()

      configs = [
        {:noop, [key: "value1"]},
        {:pid, [target: test_pid]}
      ]

      {:ok, [route]} = Validator.normalize({path, configs})
      assert route.path == path
      assert length(route.target) == 2

      noop_config = Enum.find(route.target, fn {adapter, _opts} -> adapter == :noop end)
      pid_config = Enum.find(route.target, fn {adapter, _opts} -> adapter == :pid end)

      assert noop_config == {:noop, [key: "value1"]}
      assert elem(pid_config, 0) == :pid
      assert Keyword.get(elem(pid_config, 1), :target) == test_pid
    end

    test "normalizes {path, [{adapter, opts}, ...]} tuple with keyword list format" do
      path = "test.path"
      test_pid = self()

      configs = [
        noop: [key: "value1"],
        pid: [target: test_pid]
      ]

      {:ok, [route]} = Validator.normalize({path, configs})
      assert route.path == path
      assert length(route.target) == 2

      noop_config = Enum.find(route.target, fn {adapter, _opts} -> adapter == :noop end)
      pid_config = Enum.find(route.target, fn {adapter, _opts} -> adapter == :pid end)

      assert noop_config == {:noop, [key: "value1"]}
      assert elem(pid_config, 0) == :pid
      assert Keyword.get(elem(pid_config, 1), :target) == test_pid
    end

    test "accepts any dispatch config list as term" do
      path = "test.path"
      # Any term is accepted as a target
      config_list = [
        {:noop, [key: "value1"]},
        {:invalid_adapter, [key: "value2"]}
      ]

      assert {:ok, [route]} = Validator.normalize({path, config_list})
      assert route.target == config_list
    end

    test "returns error for invalid route specification" do
      assert {:error, error} = Validator.normalize({:invalid, "format"})
      assert error.type == :validation_error
      assert error.message == "Invalid route specification format"
    end
  end

  describe "validate/1" do
    test "validates valid Route struct" do
      route = %Router.Route{
        path: "test.path",
        target: %Instruction{action: TestAction},
        priority: 0
      }

      assert {:ok, ^route} = Router.validate(route)
    end

    test "validates list of valid Route structs" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction},
          priority: 10
        }
      ]

      assert {:ok, validated} = Router.validate(routes)
      assert length(validated) == 2
      assert Enum.all?(validated, &match?(%Router.Route{}, &1))
    end

    test "validates route with single dispatch config" do
      route = %Router.Route{
        path: "test.path",
        target: {:noop, [key: "value"]}
      }

      assert {:ok, ^route} = Router.validate(route)
    end

    test "validates route with multiple dispatch configs" do
      test_pid = self()

      configs = [
        {:noop, [key: "value1"]},
        {:pid, [target: test_pid]}
      ]

      route = %Router.Route{
        path: "test.path",
        target: configs
      }

      {:ok, validated_route} = Router.validate(route)
      assert validated_route.path == route.path
      assert length(validated_route.target) == 2

      noop_config = Enum.find(validated_route.target, fn {adapter, _opts} -> adapter == :noop end)
      pid_config = Enum.find(validated_route.target, fn {adapter, _opts} -> adapter == :pid end)

      assert noop_config == {:noop, [key: "value1"]}
      assert elem(pid_config, 0) == :pid
      assert Keyword.get(elem(pid_config, 1), :target) == test_pid
    end

    test "returns error for invalid path format" do
      route = %Router.Route{
        path: "invalid..path",
        target: %Instruction{action: TestAction}
      }

      assert {:error, error} = Router.validate(route)
      assert error.type == :routing_error
      assert error.message == "Path cannot contain consecutive dots"

      # Test invalid path with '**' sequence
      route_with_double_star = %Router.Route{
        path: "invalid**path",
        target: %Instruction{action: TestAction}
      }

      assert {:error, error} = Router.validate(route_with_double_star)
      assert error.type == :routing_error
      assert error.message == "Path cannot contain '**' sequence"

      # Test invalid characters
      route_with_invalid_chars = %Router.Route{
        path: "invalid@#path",
        target: %Instruction{action: TestAction}
      }

      assert {:error, error} = Router.validate(route_with_invalid_chars)
      assert error.type == :routing_error
      assert error.message == "Path contains invalid characters"
    end

    test "accepts any target term" do
      route = %Router.Route{
        path: "test.path",
        target: :invalid
      }

      assert {:ok, validated_route} = Router.validate(route)
      assert validated_route.target == :invalid
    end

    test "accepts any dispatch config term" do
      route = %Router.Route{
        path: "test.path",
        target: {"not_an_atom", []}
      }

      assert {:ok, validated_route} = Router.validate(route)
      assert validated_route.target == {"not_an_atom", []}
    end

    test "returns error for invalid priority" do
      route = %Router.Route{
        path: "test.path",
        target: %Instruction{action: TestAction},
        # Above max allowed
        priority: 101
      }

      assert {:error, error} = Router.validate(route)
      assert error.type == :routing_error
      assert error.message == "Priority value exceeds maximum allowed"
    end

    test "returns error for invalid match function" do
      route = %Router.Route{
        path: "test.path",
        target: %Instruction{action: TestAction},
        match: "not_a_function"
      }

      assert {:error, error} = Router.validate(route)
      assert error.type == :routing_error
      assert error.message == "Match must be a function that takes one argument"
    end

    test "returns error for invalid input type" do
      assert {:error, error} = Router.validate(:invalid)
      assert error.type == :validation_error
      assert error.message == "Expected Route struct or list of Route structs"
    end
  end

  describe "new/1" do
    test "creates router with single route" do
      route = %Router.Route{
        path: "test.path",
        target: %Instruction{action: TestAction}
      }

      assert {:ok, router} = Router.new(route)
      assert router.route_count == 1
      assert %Router.TrieNode{} = router.trie

      # Check the trie structure matches what we expect
      assert %Router.TrieNode{
               segments: %{
                 "test" => %Router.TrieNode{
                   segments: %{
                     "path" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             target: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     }
                   }
                 }
               }
             } = router.trie
    end

    test "creates router with multiple routes" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      assert {:ok, router} = Router.new(routes)
      assert router.route_count == 2
      assert %Router.TrieNode{} = router.trie

      # Check the trie structure matches what we expect
      assert %Router.TrieNode{
               segments: %{
                 "test" => %Router.TrieNode{
                   segments: %{
                     "path1" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             target: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     },
                     "path2" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             target: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     }
                   }
                 }
               }
             } = router.trie
    end

    test "creates empty router with nil input" do
      assert {:ok, router} = Router.new(nil)
      assert router.route_count == 0
      assert %Router.TrieNode{} = router.trie
      assert router.trie.segments == %{}
    end
  end

  describe "add/2" do
    test "adds a single route" do
      {:ok, router} = Router.new(nil)

      route = %Router.Route{
        path: "test.path",
        target: %Instruction{action: TestAction}
      }

      assert {:ok, updated} = Router.add(router, route)
      assert updated.route_count == 1

      assert %Router.TrieNode{
               segments: %{
                 "test" => %Router.TrieNode{
                   segments: %{
                     "path" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             target: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     }
                   }
                 }
               }
             } = updated.trie
    end

    test "adds multiple routes" do
      {:ok, router} = Router.new(nil)

      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      assert {:ok, updated} = Router.add(router, routes)
      assert updated.route_count == 2
    end
  end

  describe "remove/2" do
    test "removes a single route" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      {:ok, router} = Router.new(routes)

      assert {:ok, updated} = Router.remove(router, "test.path1")
      assert updated.route_count == 1

      assert %Router.TrieNode{
               segments: %{
                 "test" => %Router.TrieNode{
                   segments: %{
                     "path2" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             target: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     }
                   }
                 }
               }
             } = updated.trie
    end

    test "removes multiple routes" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      {:ok, router} = Router.new(routes)

      assert {:ok, updated} = Router.remove(router, ["test.path1", "test.path2"])
      assert updated.route_count == 0
      assert updated.trie.segments == %{}
    end
  end

  describe "list_routes/1" do
    test "lists all routes" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      {:ok, router} = Router.new(routes)

      assert {:ok, listed_routes} = Router.list(router)
      assert length(listed_routes) == 2

      assert Enum.all?(listed_routes, fn route ->
               match?(
                 %Router.Route{
                   target: %Instruction{action: TestAction},
                   priority: 0
                 },
                 route
               )
             end)

      assert Enum.map(listed_routes, & &1.path) |> Enum.sort() == ["test.path1", "test.path2"]
    end

    test "lists empty routes" do
      {:ok, router} = Router.new(nil)
      assert {:ok, []} = Router.list(router)
    end
  end

  describe "merge/2" do
    test "merges two routers" do
      routes1 = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          target: %Instruction{action: TestAction}
        }
      ]

      routes2 = [
        %Router.Route{
          path: "test.path3",
          target: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path4",
          target: %Instruction{action: TestAction}
        }
      ]

      {:ok, router1} = Router.new(routes1)
      {:ok, router2} = Router.new(routes2)

      assert {:ok, merged} = Router.merge(router1, router2)
      assert merged.route_count == 4

      assert {:ok, merged_routes} = Router.list(merged)
      assert length(merged_routes) == 4

      paths = merged_routes |> Enum.map(& &1.path) |> Enum.sort()
      assert paths == ["test.path1", "test.path2", "test.path3", "test.path4"]
    end

    test "merges empty routers" do
      {:ok, router1} = Router.new(nil)
      {:ok, router2} = Router.new(nil)

      assert {:ok, merged} = Router.merge(router1, router2)
      assert merged.route_count == 0
      assert {:ok, []} = Router.list(merged)
    end

    test "merges router with empty router" do
      routes = [
        %Router.Route{
          path: "test.path1",
          target: %Instruction{action: TestAction}
        }
      ]

      {:ok, router1} = Router.new(routes)
      {:ok, router2} = Router.new(nil)

      assert {:ok, merged} = Router.merge(router1, router2)
      assert merged.route_count == 1

      assert {:ok, [route]} = Router.list(merged)
      assert route.path == "test.path1"
    end

    test "merges routers with duplicate routes" do
      routes1 = [
        %Router.Route{
          path: "test.path",
          target: %Instruction{action: TestAction1}
        }
      ]

      routes2 = [
        %Router.Route{
          path: "test.path",
          target: %Instruction{action: TestAction2}
        }
      ]

      {:ok, router1} = Router.new(routes1)
      {:ok, router2} = Router.new(routes2)

      assert {:ok, merged} = Router.merge(router1, router2)
      assert merged.route_count == 2

      assert {:ok, routes} = Router.list(merged)
      assert length(routes) == 2

      [route1, route2] = routes
      assert route1.path == "test.path"
      assert route2.path == "test.path"
      assert route1.target.action == TestAction1
      assert route2.target.action == TestAction2
    end
  end
end

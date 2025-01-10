defmodule Jido.Signal.RouterDefinitionTest do
  use ExUnit.Case, async: true

  alias Jido.Instruction
  alias Jido.Signal.Router

  @moduletag :capture_log

  describe "normalize/1" do
    test "normalizes single Route struct" do
      route = %Router.Route{
        path: "test.path",
        instruction: %Instruction{action: TestAction}
      }

      assert {:ok, [^route]} = Router.normalize(route)
    end

    test "normalizes list of Route structs" do
      routes = [
        %Router.Route{path: "test.1", instruction: %Instruction{action: TestAction1}},
        %Router.Route{path: "test.2", instruction: %Instruction{action: TestAction2}}
      ]

      assert {:ok, ^routes} = Router.normalize(routes)
    end

    test "normalizes {path, instruction} tuple" do
      path = "test.path"
      instruction = %Instruction{action: TestAction}

      assert {:ok, [%Router.Route{path: ^path, instruction: ^instruction}]} =
               Router.normalize({path, instruction})
    end

    test "normalizes {path, instruction, priority} tuple" do
      path = "test.path"
      instruction = %Instruction{action: TestAction}
      priority = 10

      assert {:ok, [%Router.Route{path: ^path, instruction: ^instruction, priority: ^priority}]} =
               Router.normalize({path, instruction, priority})
    end

    test "normalizes {path, match_fn, instruction} tuple" do
      path = "test.path"
      instruction = %Instruction{action: TestAction}
      match_fn = fn _signal -> true end

      assert {:ok, [%Router.Route{path: ^path, instruction: ^instruction, match: ^match_fn}]} =
               Router.normalize({path, match_fn, instruction})
    end

    test "normalizes {path, match_fn, instruction, priority} tuple" do
      path = "test.path"
      instruction = %Instruction{action: TestAction}
      match_fn = fn _signal -> true end
      priority = 10

      assert {:ok,
              [
                %Router.Route{
                  path: ^path,
                  instruction: ^instruction,
                  match: ^match_fn,
                  priority: ^priority
                }
              ]} = Router.normalize({path, match_fn, instruction, priority})
    end

    test "returns error for invalid route specification" do
      assert {:error, _} = Router.normalize({:invalid, "format"})
    end
  end

  describe "validate/1" do
    test "validates valid Route struct" do
      route = %Router.Route{
        path: "test.path",
        instruction: %Instruction{action: TestAction},
        priority: 0
      }

      assert {:ok, ^route} = Router.validate(route)
    end

    test "validates list of valid Route structs" do
      routes = [
        %Router.Route{
          path: "test.path1",
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction},
          priority: 10
        }
      ]

      assert {:ok, validated} = Router.validate(routes)
      assert length(validated) == 2
      assert Enum.all?(validated, &match?(%Router.Route{}, &1))
    end

    test "returns error for invalid path format" do
      route = %Router.Route{
        path: "invalid..path",
        instruction: %Instruction{action: TestAction}
      }

      assert {:error, _} = Router.validate(route)
    end

    test "returns error for invalid instruction" do
      route = %Router.Route{
        path: "test.path",
        instruction: :invalid
      }

      assert {:error, _} = Router.validate(route)
    end

    test "returns error for invalid priority" do
      route = %Router.Route{
        path: "test.path",
        instruction: %Instruction{action: TestAction},
        # Above max allowed
        priority: 101
      }

      assert {:error, _} = Router.validate(route)
    end

    test "returns error for invalid match function" do
      route = %Router.Route{
        path: "test.path",
        instruction: %Instruction{action: TestAction},
        match: "not_a_function"
      }

      assert {:error, _} = Router.validate(route)
    end

    test "returns error for invalid input type" do
      assert {:error, _} = Router.validate(:invalid)
    end
  end

  describe "new/1" do
    test "creates router with single route" do
      route = %Router.Route{
        path: "test.path",
        instruction: %Instruction{action: TestAction}
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
                             instruction: %Instruction{action: TestAction},
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
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
                             instruction: %Instruction{action: TestAction},
                             priority: 0
                           }
                         ]
                       }
                     },
                     "path2" => %Router.TrieNode{
                       handlers: %Router.NodeHandlers{
                         handlers: [
                           %Router.HandlerInfo{
                             instruction: %Instruction{action: TestAction},
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
        instruction: %Instruction{action: TestAction}
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
                             instruction: %Instruction{action: TestAction},
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
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
                             instruction: %Instruction{action: TestAction},
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
        }
      ]

      {:ok, router} = Router.new(routes)

      assert {:ok, listed_routes} = Router.list(router)
      assert length(listed_routes) == 2

      assert Enum.all?(listed_routes, fn route ->
               match?(
                 %Router.Route{
                   instruction: %Instruction{action: TestAction},
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
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path2",
          instruction: %Instruction{action: TestAction}
        }
      ]

      routes2 = [
        %Router.Route{
          path: "test.path3",
          instruction: %Instruction{action: TestAction}
        },
        %Router.Route{
          path: "test.path4",
          instruction: %Instruction{action: TestAction}
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
          instruction: %Instruction{action: TestAction}
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
          instruction: %Instruction{action: TestAction1}
        }
      ]

      routes2 = [
        %Router.Route{
          path: "test.path",
          instruction: %Instruction{action: TestAction2}
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
      assert route1.instruction.action == TestAction1
      assert route2.instruction.action == TestAction2
    end
  end
end

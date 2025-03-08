defmodule Jido.Actions.StateManagerTest do
  use JidoTest.Case, async: true
  alias Jido.Actions.StateManager
  alias Jido.Agent.Directive.StateModification

  @moduletag :capture_log

  # Helper function to apply state modifications
  defp apply_modifications(state, modifications) do
    Enum.reduce(modifications, state, fn
      %StateModification{op: :set, path: path, value: value}, acc ->
        put_in(acc, path, value)

      %StateModification{op: :delete, path: path}, acc ->
        {_, new_state} = pop_in(acc, path)
        new_state
    end)
  end

  describe "Get" do
    test "gets a value from a simple path" do
      state = %{foo: "bar"}
      assert {:ok, %{value: "bar"}, []} = StateManager.Get.run(%{path: [:foo]}, %{state: state})
    end

    test "gets a value from a nested path" do
      state = %{foo: %{bar: %{baz: "value"}}}

      assert {:ok, %{value: "value"}, []} =
               StateManager.Get.run(%{path: [:foo, :bar, :baz]}, %{state: state})
    end

    test "returns nil for non-existent path" do
      state = %{foo: %{bar: "baz"}}

      assert {:ok, %{value: nil}, []} =
               StateManager.Get.run(%{path: [:foo, :nonexistent]}, %{state: state})
    end

    test "handles deeply nested maps" do
      state = %{
        a: %{
          b: %{
            c: %{
              d: %{
                e: "value"
              }
            }
          }
        }
      }

      assert {:ok, %{value: "value"}, []} =
               StateManager.Get.run(%{path: [:a, :b, :c, :d, :e]}, %{state: state})
    end

    test "handles mixed nested structures" do
      state = %{
        foo: %{
          bar: [
            %{id: 1, value: "one"},
            %{id: 2, value: "two"}
          ],
          baz: %{
            nested: %{value: "deep"}
          }
        }
      }

      assert {:ok, %{value: "deep"}, []} =
               StateManager.Get.run(%{path: [:foo, :baz, :nested, :value]}, %{state: state})
    end
  end

  describe "Set" do
    test "sets a value at a simple path" do
      state = %{}

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo], value: "bar"}, %{state: state})

      assert length(modifications) == 1
      [directive] = modifications
      assert directive.op == :set
      assert directive.path == [:foo]
      assert directive.value == "bar"

      state = apply_modifications(state, modifications)
      assert state == %{foo: "bar"}
    end

    test "sets a value at a nested path" do
      state = %{foo: %{bar: %{}}}

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo, :bar, :baz], value: "value"}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{bar: %{baz: "value"}}}
    end

    test "overwrites existing value" do
      state = %{foo: "old"}

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo], value: "new"}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: "new"}
    end

    test "creates deeply nested structure" do
      state = %{}

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:a, :b, :c, :d, :e], value: "value"}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{a: %{b: %{c: %{d: %{e: "value"}}}}}
    end

    test "preserves existing nested structure" do
      state = %{
        foo: %{
          bar: %{existing: "value"},
          baz: %{other: "value"}
        }
      }

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo, :bar, :new], value: "value"}, %{state: state})

      state = apply_modifications(state, modifications)

      assert state == %{
               foo: %{
                 bar: %{existing: "value", new: "value"},
                 baz: %{other: "value"}
               }
             }
    end

    test "handles mixed nested structures" do
      state = %{
        foo: %{
          bar: [
            %{id: 1, value: "one"},
            %{id: 2, value: "two"}
          ]
        }
      }

      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo, :baz, :nested, :value], value: "deep"}, %{
          state: state
        })

      state = apply_modifications(state, modifications)

      assert state == %{
               foo: %{
                 bar: [
                   %{id: 1, value: "one"},
                   %{id: 2, value: "two"}
                 ],
                 baz: %{nested: %{value: "deep"}}
               }
             }
    end
  end

  describe "Update" do
    test "updates a value" do
      state = %{counter: 5}

      {:ok, state, modifications} =
        StateManager.Update.run(%{path: [:counter], value: 6}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{counter: 6}
    end

    test "updates a nested value" do
      state = %{foo: %{bar: %{counter: 5}}}

      {:ok, state, modifications} =
        StateManager.Update.run(%{path: [:foo, :bar, :counter], value: 6}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{bar: %{counter: 6}}}
    end

    test "handles nil values" do
      state = %{foo: nil}

      {:ok, state, modifications} =
        StateManager.Update.run(%{path: [:foo], value: 1}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: 1}
    end

    test "updates deeply nested value" do
      state = %{
        a: %{
          b: %{
            c: %{
              d: %{
                e: "old"
              }
            }
          }
        }
      }

      {:ok, state, modifications} =
        StateManager.Update.run(%{path: [:a, :b, :c, :d, :e], value: "new"}, %{state: state})

      state = apply_modifications(state, modifications)

      assert state == %{
               a: %{
                 b: %{
                   c: %{
                     d: %{
                       e: "new"
                     }
                   }
                 }
               }
             }
    end

    test "preserves other nested values" do
      state = %{
        foo: %{
          bar: %{value: "old"},
          baz: %{value: "other"}
        }
      }

      {:ok, state, modifications} =
        StateManager.Update.run(%{path: [:foo, :bar, :value], value: "new"}, %{state: state})

      state = apply_modifications(state, modifications)

      assert state == %{
               foo: %{
                 bar: %{value: "new"},
                 baz: %{value: "other"}
               }
             }
    end
  end

  describe "Delete" do
    test "deletes a value at a simple path" do
      state = %{foo: "bar", baz: "qux"}
      {:ok, state, modifications} = StateManager.Delete.run(%{path: [:foo]}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{baz: "qux"}
    end

    test "deletes a value at a nested path" do
      state = %{foo: %{bar: %{baz: "value"}}}

      {:ok, state, modifications} =
        StateManager.Delete.run(%{path: [:foo, :bar, :baz]}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{bar: %{}}}
    end

    test "handles empty path" do
      state = %{foo: "bar"}
      assert {:ok, ^state, []} = StateManager.Delete.run(%{path: []}, %{state: state})
    end

    test "deletes deeply nested value" do
      state = %{
        a: %{
          b: %{
            c: %{
              d: %{
                e: "value"
              }
            }
          }
        }
      }

      {:ok, state, modifications} =
        StateManager.Delete.run(%{path: [:a, :b, :c, :d, :e]}, %{state: state})

      state = apply_modifications(state, modifications)

      assert state == %{
               a: %{
                 b: %{
                   c: %{
                     d: %{}
                   }
                 }
               }
             }
    end

    test "preserves other nested values when deleting" do
      state = %{
        foo: %{
          bar: %{value: "one"},
          baz: %{value: "two"}
        }
      }

      {:ok, state, modifications} =
        StateManager.Delete.run(%{path: [:foo, :bar, :value]}, %{state: state})

      state = apply_modifications(state, modifications)

      assert state == %{
               foo: %{
                 bar: %{},
                 baz: %{value: "two"}
               }
             }
    end
  end

  describe "Integration" do
    test "performs multiple operations in sequence" do
      # Initial state
      state = %{}

      # Set nested value
      {:ok, state, modifications} =
        StateManager.Set.run(%{path: [:foo, :bar], value: "baz"}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{bar: "baz"}}

      # Get the value
      {:ok, %{value: "baz"}, []} = StateManager.Get.run(%{path: [:foo, :bar]}, %{state: state})

      # Update the value
      {:ok, state, modifications} =
        StateManager.Update.run(
          %{path: [:foo, :bar], value: "BAZ"},
          %{state: state}
        )

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{bar: "BAZ"}}

      # Delete the value
      {:ok, state, modifications} =
        StateManager.Delete.run(%{path: [:foo, :bar]}, %{state: state})

      state = apply_modifications(state, modifications)
      assert state == %{foo: %{}}
    end

    test "handles complex nested operations" do
      # Initial state with nested structure
      state = %{
        foo: %{
          bar: %{
            baz: "value"
          }
        }
      }

      # Set deeply nested value
      {:ok, state, modifications} =
        StateManager.Set.run(
          %{path: [:foo, :bar, :qux, :deep], value: "new"},
          %{state: state}
        )

      state = apply_modifications(state, modifications)
      assert get_in(state, [:foo, :bar, :qux, :deep]) == "new"
      assert get_in(state, [:foo, :bar, :baz]) == "value"

      # Update existing nested value
      {:ok, state, modifications} =
        StateManager.Update.run(
          %{path: [:foo, :bar, :baz], value: "updated"},
          %{state: state}
        )

      state = apply_modifications(state, modifications)
      assert get_in(state, [:foo, :bar, :baz]) == "updated"
      assert get_in(state, [:foo, :bar, :qux, :deep]) == "new"

      # Delete nested value
      {:ok, state, modifications} =
        StateManager.Delete.run(
          %{path: [:foo, :bar, :qux, :deep]},
          %{state: state}
        )

      state = apply_modifications(state, modifications)
      assert get_in(state, [:foo, :bar, :qux, :deep]) == nil
      assert get_in(state, [:foo, :bar, :baz]) == "updated"
    end
  end
end

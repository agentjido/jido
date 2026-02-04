# Jido.Skill → Jido.Plugin Migration Plan

**Status:** Breaking change, no backwards compatibility  
**Reason:** "Skill" conflicts with LLM/AI concept of Skills (e.g., skills.sh). "Plugin" better describes the role as a composable extension point.

---

## Summary

| Metric | Count |
|--------|-------|
| Files to rename | 11 |
| Files to modify | 36 |
| Total references | ~337 |

---

## Phase 1: Core Module Renames

### 1.1 Main Module + Directory

| From | To |
|------|-----|
| `lib/jido/skill.ex` | `lib/jido/plugin.ex` |
| `lib/jido/skill/` | `lib/jido/plugin/` |

### 1.2 Nested Modules (in `lib/jido/skill/`)

| From | To |
|------|-----|
| `lib/jido/skill/config.ex` | `lib/jido/plugin/config.ex` |
| `lib/jido/skill/instance.ex` | `lib/jido/plugin/instance.ex` |
| `lib/jido/skill/manifest.ex` | `lib/jido/plugin/manifest.ex` |
| `lib/jido/skill/requirements.ex` | `lib/jido/plugin/requirements.ex` |
| `lib/jido/skill/routes.ex` | `lib/jido/plugin/routes.ex` |
| `lib/jido/skill/schedules.ex` | `lib/jido/plugin/schedules.ex` |
| `lib/jido/skill/spec.ex` | `lib/jido/plugin/spec.ex` |

### 1.3 Mix Task

| From | To |
|------|-----|
| `lib/mix/tasks/jido.gen.skill.ex` | `lib/mix/tasks/jido.gen.plugin.ex` |

---

## Phase 2: Module Namespace Changes

All modules need their `defmodule` declarations updated:

```elixir
# Before                          # After
Jido.Skill                    →   Jido.Plugin
Jido.Skill.Config             →   Jido.Plugin.Config
Jido.Skill.Instance           →   Jido.Plugin.Instance
Jido.Skill.Manifest           →   Jido.Plugin.Manifest
Jido.Skill.Requirements       →   Jido.Plugin.Requirements
Jido.Skill.Routes             →   Jido.Plugin.Routes
Jido.Skill.Schedules          →   Jido.Plugin.Schedules
Jido.Skill.Spec               →   Jido.Plugin.Spec
Mix.Tasks.Jido.Gen.Skill      →   Mix.Tasks.Jido.Gen.Plugin
```

---

## Phase 3: Callback & Function Renames

### 3.1 Behaviour Callbacks

| From | To |
|------|-----|
| `@callback skill_spec(config :: map()) :: Spec.t()` | `@callback plugin_spec(config :: map()) :: Spec.t()` |

### 3.2 Generated Functions

| From | To |
|------|-----|
| `def skill_spec(config \\ %{})` | `def plugin_spec(config \\ %{})` |
| `def __skill_metadata__()` | `def __plugin_metadata__()` |

### 3.3 @impl Tags

```elixir
# Before                    # After
@impl Jido.Skill        →   @impl Jido.Plugin
```

---

## Phase 4: Agent Integration Changes

### 4.1 Use Macro Option

```elixir
# Before
use Jido.Agent,
  skills: [MyApp.ChatSkill, {MyApp.DatabaseSkill, %{pool_size: 5}}]

# After
use Jido.Agent,
  plugins: [MyApp.ChatPlugin, {MyApp.DatabasePlugin, %{pool_size: 5}}]
```

### 4.2 Schema Field in `lib/jido/agent/schema.ex`

```elixir
# Before                    # After
skills: [...]           →   plugins: [...]
```

### 4.3 Files Requiring `skills:` → `plugins:` Updates

- `lib/jido/agent.ex`
- `lib/jido/agent/schema.ex`
- `lib/jido/agent_server.ex`
- `lib/jido/agent_server/signal_router.ex`

---

## Phase 5: Internal Variable/Key Renames

These are internal naming conventions that should be updated for consistency:

| From | To |
|------|-----|
| `@skill_config_schema` | `@plugin_config_schema` |
| `:skill` (in context maps) | `:plugin` |
| `:skill_spec` (in context maps) | `:plugin_spec` |
| `skill_state` | `plugin_state` |

---

## Phase 6: Discovery Integration

Update `lib/jido/discovery.ex`:

| From | To |
|------|-----|
| `__skill_metadata__/0` calls | `__plugin_metadata__/0` calls |
| `:skill` type references | `:plugin` type references |

---

## Phase 7: Test File Renames

### 7.1 Test Files to Rename

| From | To |
|------|-----|
| `test/jido/skill/skill_test.exs` | `test/jido/plugin/plugin_test.exs` |
| `test/jido/skill/skill_lifecycle_test.exs` | `test/jido/plugin/plugin_lifecycle_test.exs` |
| `test/jido/skill/skill_mount_test.exs` | `test/jido/plugin/plugin_mount_test.exs` |
| `test/jido/skill/config_test.exs` | `test/jido/plugin/config_test.exs` |
| `test/jido/skill/instance_test.exs` | `test/jido/plugin/instance_test.exs` |
| `test/jido/skill/manifest_test.exs` | `test/jido/plugin/manifest_test.exs` |
| `test/jido/skill/requirements_test.exs` | `test/jido/plugin/requirements_test.exs` |
| `test/jido/skill/routes_test.exs` | `test/jido/plugin/routes_test.exs` |
| `test/jido/skill/schedules_test.exs` | `test/jido/plugin/schedules_test.exs` |
| `test/jido/agent_skill_integration_test.exs` | `test/jido/agent_plugin_integration_test.exs` |
| `test/jido/agent_server/skill_children_test.exs` | `test/jido/agent_server/plugin_children_test.exs` |
| `test/jido/agent_server/skill_signal_hooks_test.exs` | `test/jido/agent_server/plugin_signal_hooks_test.exs` |
| `test/jido/agent_server/skill_subscriptions_test.exs` | `test/jido/agent_server/plugin_subscriptions_test.exs` |
| `test/jido/agent_server/skill_transform_test.exs` | `test/jido/agent_server/plugin_transform_test.exs` |

### 7.2 Test Module Namespace Updates

```elixir
# Before                              # After
JidoTest.Skill.*                  →   JidoTest.Plugin.*
JidoTest.AgentSkillIntegration    →   JidoTest.AgentPluginIntegration
```

---

## Phase 8: Support Files

Update `test/support/test_agents.ex`:
- Rename any `TestSkill` modules to `TestPlugin`
- Update `use Jido.Skill` to `use Jido.Plugin`
- Update `skills:` to `plugins:`

---

## Phase 9: Documentation Updates

### 9.1 Moduledocs and @doc

All `@moduledoc` and `@doc` strings referencing "Skill" should say "Plugin":

- "A Skill is a composable capability..." → "A Plugin is a composable capability..."
- "skills:" → "plugins:" in examples
- "MyApp.ChatSkill" → "MyApp.ChatPlugin" in examples

### 9.2 Guides

Check `guides/` directory for any skill-related documentation.

### 9.3 AGENTS.md

Update architecture table and examples that reference skills.

---

## Phase 10: Igniter Templates

Update `lib/jido/igniter/templates.ex`:
- Template content referencing skills
- Generated code examples

---

## Execution Order

1. **Create new directories**: `lib/jido/plugin/`, `test/jido/plugin/`
2. **Move and rename files**: Phase 1
3. **Update module declarations**: Phase 2
4. **Update callbacks and functions**: Phase 3
5. **Update Agent integration**: Phase 4
6. **Update internal naming**: Phase 5
7. **Update Discovery**: Phase 6
8. **Move and rename test files**: Phase 7
9. **Update support files**: Phase 8
10. **Update documentation**: Phase 9
11. **Update templates**: Phase 10
12. **Delete empty `lib/jido/skill/` and `test/jido/skill/` directories**

---

## Verification Checklist

After migration, run:

```bash
# Compile with warnings as errors
mix compile --warnings-as-errors

# Run all tests
mix test

# Run quality checks
mix quality

# Verify no skill references remain (Jido-context only)
grep -r "Jido\.Skill\|skill_spec\|__skill_metadata__\|skills:" lib test

# Should return 0 matches
```

---

## Files Summary

### Files to Rename (11 total)

**lib/ (8 files)**
1. `lib/jido/skill.ex` → `lib/jido/plugin.ex`
2. `lib/jido/skill/config.ex` → `lib/jido/plugin/config.ex`
3. `lib/jido/skill/instance.ex` → `lib/jido/plugin/instance.ex`
4. `lib/jido/skill/manifest.ex` → `lib/jido/plugin/manifest.ex`
5. `lib/jido/skill/requirements.ex` → `lib/jido/plugin/requirements.ex`
6. `lib/jido/skill/routes.ex` → `lib/jido/plugin/routes.ex`
7. `lib/jido/skill/schedules.ex` → `lib/jido/plugin/schedules.ex`
8. `lib/jido/skill/spec.ex` → `lib/jido/plugin/spec.ex`
9. `lib/mix/tasks/jido.gen.skill.ex` → `lib/mix/tasks/jido.gen.plugin.ex`

**test/ (14 files)**
1. `test/jido/skill/` → `test/jido/plugin/` (entire directory)
2. `test/jido/agent_skill_integration_test.exs` → `test/jido/agent_plugin_integration_test.exs`
3. `test/jido/agent_server/skill_*.exs` → `test/jido/agent_server/plugin_*.exs` (4 files)

### Files to Modify (content updates only)

**lib/ (6 files)**
1. `lib/jido/agent.ex`
2. `lib/jido/agent/schema.ex`
3. `lib/jido/agent_server.ex`
4. `lib/jido/agent_server/signal_router.ex`
5. `lib/jido/discovery.ex`
6. `lib/jido/igniter/templates.ex`
7. `lib/mix/tasks/jido.gen.agent.ex`

**test/ (5 files)**
1. `test/jido/agent/agent_test.exs`
2. `test/jido/agent/schema_coverage_test.exs`
3. `test/jido/agent/schema_test.exs`
4. `test/jido/agent_server/agent_server_test.exs`
5. `test/jido/agent_server/signal_router_test.exs`
6. `test/support/test_agents.ex`

---

## Estimated Effort

**Time:** 2-4 hours  
**Risk:** Medium (many files, but purely mechanical rename)  
**Testing:** Full test suite must pass after migration

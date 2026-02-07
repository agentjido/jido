# CHANGELOG

<!-- %% CHANGELOG_ENTRIES %% -->

## 2.0.0-rc.4 - 2026-02-06

### Added
- Memory plugin: implement `Jido.Memory` as default plugin under `__memory__` key (#125)
- Identity plugin: add `Jido.Identity` as default agent plugin (#126)
- Plugin singleton flag in plugin config schema (#120)
- Plugin signal middleware improvements (#123)

### Changed
- Update `signal_routes` to accept context parameter (#121)

### Fixed
- Wire `on_restore/2` into generated `restore/2` callback (#122)

### Tests & Chores
- Add memory plugin and default plugins persistence examples (#127)
- Organize example tests into subdirectories (#124)
- Add `Jido.Plugin` to doctor ignore_modules for macro-generated defs
- Remove AI cruft and build artifacts

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.4

---

## 2.0.0-rc.3 - 2026-02-04

### Added
- `cmd/3` to support per-action timeout opts (#117)
- Unified persistence layer for agent checkpoints and thread journals (#110)
- Telemetry infrastructure with span tracking and metrics (#109)
- Debug helpers and improved timeout errors (#111)

### Changed
- **BREAKING**: Renamed `Jido.Skill` to `Jido.Plugin` (#115)

### Fixed
- Dialyzer/Credo: add :mix to PLT, remove unnecessary ignores (#118)

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.3
- Bump `ex_doc` from 0.40.0 to 0.40.1 (#112)

---

## 2.0.0-rc.2 - 2025-01-30

### Changed
- **Zoi Schema Migration**: Convert remaining structs to use Zoi schemas for consistent validation (#106)
- **Macro Decomposition**: Decompose large macros and improve code organization (#101)
- **Sensor Simplification**: Simplify `handle_event/2` to directive-only format (#108)

### Fixed
- Address code quality issues from codebase review (#107)
- Improve process lifecycle handling and test reliability (#100)

### Dependencies
- Bump `jido_action` and `jido_signal` to 2.0.0-rc.2

---

## 2.0.0 - 2025-12-31

### Added
- **Instance-Scoped Supervisors**: Jido now uses user-owned, instance-scoped supervisors instead of auto-started global singletons
- **Jido Supervisor Module**: New `Jido` module acts as a Supervisor managing per-instance Registry, TaskSupervisor, and AgentSupervisor
- **Agent Lifecycle API**: New functions `Jido.start_agent/3`, `Jido.stop_agent/2`, `Jido.whereis/2`, `Jido.list_agents/1`
- **Test Isolation**: New `JidoTest.Case` module for automatic test isolation with unique Jido instances
- **Per-Instance Scheduler**: Scheduler can now be scoped to a Jido instance
- **Multi-Agent Coordination**: New `Jido.await/3` and `Jido.await_child/4` for coordinating agent completion
- **Discovery Delegates**: Discovery functions accessible via main Jido module

### Breaking Changes
- **Explicit Supervision**: Users must now add `{Jido, name: MyApp.Jido}` to their supervision tree
- **Agent Start**: Use `Jido.start_agent(instance, agent, opts)` instead of `AgentServer.start/1`
- **Instance Option**: Pass `jido: MyApp.Jido` option when starting agents directly

### Changed
- Refactored from global singletons to instance-scoped architecture
- Agents now register in instance-specific Registry
- TaskSupervisor and AgentSupervisor are per-instance
- Updated all examples to use new 2.0 patterns

### Migration from 1.x
See the Migration section in README.md for upgrade instructions.

---

## Unreleased - 2025-08-29

### Added
- **Modular API Architecture**: Refactored monolithic `Jido.ex` module into specialized modules:
  - `Jido.Agent.Lifecycle` - Agent lifecycle management (start, stop, restart, clone operations)
  - `Jido.Agent.Interaction` - Agent communication (signals, instructions, requests)
  - `Jido.Agent.Utilities` - Helper functions (via/2, resolve_pid/1, generate_id/0, log_level/2)
- **Comprehensive Test Helpers**: New `JidoTest.Support` module with common test utilities:
  - Registry management helpers (`start_registry!/0`)
  - Agent lifecycle helpers (`start_basic_agent!/1`, automatic cleanup)
  - Signal and state assertion helpers
  - Consistent test patterns across all modules
- **Table-Driven Test Coverage**: Implemented data-driven delegation tests for maintainable 100% API coverage
- **Performance-Optimized Test Suite**: Consolidated and streamlined tests with `@tag :slow` for optional performance tests

### Breaking Changes
- **None**: All public API functions remain fully backward compatible through delegation in main `Jido` module

### Changed
- **Improved Test Performance**: ~40% reduction in test execution time through:
  - Elimination of redundant test cases
  - Reduced UUID generation from thousands to ~110 total
  - Parameterized test scenarios instead of copy-paste patterns
  - Common setup helpers reducing boilerplate
- **Enhanced Test Maintainability**: 
  - Centralized test helpers eliminate code duplication
  - Table-driven tests make adding new API methods trivial
  - Consistent patterns across all test files
- **Better Resource Management**: Automatic test cleanup prevents resource leaks and test isolation issues

### Fixed
- **Test Suite Optimization**: Removed redundant tests while maintaining high coverage (68.4% overall, >80% for key modules)
- **Code Quality**: Addressed Credo warnings in test files (replaced `length/1` with `Enum.empty?/1`)

---

## Previous - 2025-08-25

### Added
- **Automatic Action Registration**: Skills can now declare required actions in their configuration using the `actions` field, which are automatically registered when the skill is mounted
- **Module Path Refactoring**: Moved action modules from `Jido.Actions.*` to `Jido.Tools.*` namespace for better alignment with `jido_action` library
- **Default Skills**: Agent server now uses default skills (`Jido.Skills.Basic` and `Jido.Skills.StateManager`) instead of hardcoded actions

### Breaking Changes
- **Action module paths**: All action modules moved from `Jido.Actions.*` to `Jido.Tools.*` to align with the `jido_action` library
- **Runner system removed**: The separate `Jido.Runner.Simple` and `Jido.Runner.Chain` modules have been deprecated. Agents now use built-in execution logic that processes one instruction at a time (equivalent to the former Simple Runner behavior)

### Changed
- **Skill configuration**: Skills can now declare required actions using the `actions` field for automatic registration
- **Agent options**: Both `actions:` and `skills:` options are supported, with skills providing the preferred declarative approach

### Fixed
- Task update action now only updates provided fields instead of overwriting with nil values
- State manager update action now uses `:update` operation instead of `:set` for proper semantic behavior
- Improved error handling for action registration failures

## 1.1.0-rc.1 - 2025-02-18

- Address open Credo Errors
- Add documentation
- Clean up README in prep for 1.1 release

## 1.1.0-rc - 2025-02-08

- Stateful Agents

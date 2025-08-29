# CHANGELOG

<!-- %% CHANGELOG_ENTRIES %% -->

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

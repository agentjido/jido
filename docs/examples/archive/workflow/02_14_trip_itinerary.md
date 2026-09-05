> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Trip Itinerary

- **ID:** `02_14_trip_itinerary`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Build a constrained itinerary from travel options.
- **User story:** As a traveler, I receive a daily plan that respects budget, dates, and interests.
- **Trigger or input:** `trip.plan` Signal with destination, dates, budget, and preferences.
- **Agent state:** Normalized constraints, selected options, daily plan, total cost, and warnings.
- **Actions or Flow:** A Flow validates constraints, queries option adapters, selects items, and checks the final plan.
- **External interactions:** Travel search APIs and optional model. Local tests use fixed option fixtures.
- **Runtime Directives or capabilities:** An optional `Emit` sends booking requests only after a separate approval Signal.
- **Expected result:** The itinerary satisfies hard constraints and lists unsupported preferences.
- **Failure cases:** No feasible plan, stale price, provider error, budget overflow, or timezone error.
- **Jido features under pressure:** Planning Flow, external reads, policy checks, human approval boundary, and typed totals.
- **Source framework and links:** [AutoGen: travel planning](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/examples/travel-planning.html), [CrewAI: surprise trip](https://github.com/crewAIInc/crewAI-examples/tree/main/crews/surprise_trip)

## Burn-in result

The local example passes. The Flow validates dates and budget, reads fixture
options, selects one option per day, and checks the final plan. Missing dates
or budget overflow fail without partial state.

## Best-effort implementation

- Code history: `git show ee1e641:lib/examples/02_workflow/02_14_trip_itinerary/trip_itinerary.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_14_trip_itinerary/trip_itinerary_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

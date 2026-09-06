> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Flight Booking Assistant

- **ID:** `02_17_flight_booking`
- **Status:** archived research profile
- **Complexity level:** 3 - LLM workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Search flight options, resolve preferences, and prepare one booking request.
- **User story:** As a traveler, I choose a suitable flight through a multi-turn structured process.
- **Trigger or input:** Trip request, option selection, preference update, approval, or cancel Signal.
- **Agent state:** Trip constraints, search revision, offered options, selection, passenger-safe data reference, approval, and booking status.
- **Actions or Flow:** A Flow searches, filters, asks for missing choices, validates the selected fare, and prepares booking.
- **External interactions:** Flight search, optional model, and booking API. Local tests use fixed fares and an in-memory booking adapter.
- **Runtime Directives or capabilities:** A booking Plugin Directive submits an approved request after commit. Scheduler can expire a held fare.
- **Expected result:** One approved selection creates at most one booking request with a stable idempotency key.
- **Failure cases:** Stale fare, no matching option, missing passenger data, approval expiry, provider timeout, duplicate booking, or cancel race.
- **Jido features under pressure:** Multi-turn Flow state, external reads and writes, approval, expiry schedule, sensitive references, and idempotency.
- **Source framework and links:** [PydanticAI: flight booking](https://pydantic.dev/docs/ai/examples/complex-workflows/flight-booking/)

## Burn-in result

The local example passes. Search, selection, approval, cancellation, booking
submission, and booking result are separate Signals and Turns. The approval
Action commits `:submitting` state and returns a custom Directive. A Plugin
without a process performs the booking in the Server-owned dispatch task and
sends one correlated result Signal back to the Actor.

The extra `BookingRuntime` module is removed. The adapter is supplied through
transient caller context; the approval Signal has empty data and the Directive
contains only the booking request and idempotency key. The success test also
checks direct evaluation: it returns a portable Directive and performs no
booking before the Server commit. Both success and provider failure produce a
later result Turn. This is a local effect example, not durable booking recovery.

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_17_flight_booking/flight_booking.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_17_flight_booking/flight_booking_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

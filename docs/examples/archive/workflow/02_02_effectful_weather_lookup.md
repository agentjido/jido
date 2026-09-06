> Donor history and research. Counts and result claims below describe an earlier
> source snapshot. Use [the core execution record](../../../migration/10-execution-record.md) for the migration result.

# Effectful Weather Lookup

- **ID:** `02_02_effectful_weather_lookup`
- **Status:** archived research profile
- **Complexity level:** 2 - Workflow
- **Feature group:** workflow
- **Test class:** local deterministic

This historical domain profile was replaced by the [Workflow SDK suite](https://github.com/mikehostetler/jido_v3/blob/ee1e641/test/examples/02_workflow/README.md).

## Profile

- **Purpose:** Show external HTTP work inside one Action with an injected client.
- **User story:** As a traveler, I ask for weather by place and receive current conditions.
- **Trigger or input:** `weather.lookup` Signal with one or more place names.
- **Agent state:** Last normalized locations, weather results, request key, and retrieval time.
- **Actions or Flow:** One Action resolves coordinates and fetches weather. A fake adapter gives fixed responses in the default test.
- **External interactions:** Geocoding and weather APIs. The Action can perform both calls before it returns.
- **Runtime Directives or capabilities:** None are required for synchronous calls. Use a Plugin Directive only when the HTTP client needs managed runtime state.
- **Expected result:** All successful results enter one complete state commit.
- **Failure cases:** Unknown place, timeout, partial provider response, rate limit, invalid units, or duplicate request.
- **Jido features under pressure:** Effectful Action contract, injected adapters, idempotency key, timeout, typed output, and one commit.
- **Source framework and links:** [PydanticAI: weather agent](https://pydantic.dev/docs/ai/examples/getting-started/weather-agent/)

## Burn-in result

The local example passes. One Action calls a process-backed fake geocoder and
weather client, gives the same request key to every call, and returns one
complete state. A partial provider failure leaves Actor state unchanged. The
provider calls that completed before the failure are not undone.

Five local tests pass. The wrapper passes the client through
`Server.call(server, signal, context: %{client: client}, timeout: timeout)`.
The Signal contains locations, units, and the request key. It contains no adapter
module or PID. Direct `cmd/3` and live Server execution produce the same Actor
and client calls. The stored checkpoint and restored Actor contain no client
or private request context.

A later Turn without a client fails without external work or a commit. A new
client can be supplied for that Turn. A repeated committed request key returns
the same Actor without repeating external work, but still advances the commit
revision from 1 to 2. These cases prove the contracts from
[issue #11](https://github.com/mikehostetler/jido_v3/issues/11) and
[issue #15](https://github.com/mikehostetler/jido_v3/issues/15).

## Best-effort implementation

- Code history: `git show ee1e641:examples/02_workflow/02_02_effectful_weather_lookup/effectful_weather_lookup.ex`
- Tests history: `git show ee1e641:test/examples/02_workflow/02_02_effectful_weather_lookup/effectful_weather_lookup_test.exs`

The local implementation passes its mock-only tests. The tests define the
current implemented scope; they do not claim full failure-matrix or live-service
coverage.

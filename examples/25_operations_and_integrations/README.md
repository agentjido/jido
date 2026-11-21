# 25 Operations and Integrations

These lessons define production boundaries with deterministic local checks.

1. [Production configuration and shutdown](25_01_production_configuration/README.md)
2. [Persistence adapter selection](25_02_persistence_selection/README.md)
3. [Secrets and credential boundaries](25_03_credential_boundaries/README.md)
4. [External adapter boundaries](25_04_external_adapter_boundary/README.md)
5. [Passive Agent Fleet measurement](25_05_passive_fleet_measurement/README.md)
6. [Security, authorization, and sandbox limits](25_06_security_boundaries/README.md)
7. [Distribution boundaries](25_07_distribution_boundaries/README.md)
8. [Offline AI provider configuration](25_08_offline_provider_configuration/README.md)

Run the chapter offline:

```sh
mix test.examples examples/25_operations_and_integrations --warnings-as-errors
```

No lesson contacts a network service or accepts a live credential.

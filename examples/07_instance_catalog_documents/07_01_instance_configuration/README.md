# 07_01 Instance configuration

Start one named Jido instance as part of an OTP supervision tree.

## What you will learn

- `use Jido` binds an instance name, OTP application, and stable namespace.
- Runtime options can bound tasks and passive Agent residency.
- Invalid options fail before the instance supervisor starts.

## Read the code

Read [the configured instance](configured_instance.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_01_instance_configuration --warnings-as-errors`

Expected result: one seven-child Jido supervision tree starts, and invalid
configuration does not leave a registered process.

## Important behavior

The host application owns instance configuration and supervision. A later call
does not reconfigure an already running instance.

## Limits

This lesson does not select a persistence adapter or prove shutdown under load.

## Files

- [Source](configured_instance.ex)
- [Tests](configured_instance_test.exs)

Next: [Namespaces and partitions](../07_02_namespaces_and_partitions/README.md)

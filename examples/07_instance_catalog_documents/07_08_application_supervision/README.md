# 07_08 Application supervision

Let one host OTP supervisor own the Jido instance and required startup Agents.

## What you will learn

- Installed Agent code and a stored Agent document are different concerns.
- A `:rest_for_one` host tree starts Jido before application bootstrap.
- Normal OTP shutdown stops the instance and every resident Agent process.

## Read the code

Read [the host supervision tree](application_supervision.ex) first.

## Run it

`mix test.examples examples/07_instance_catalog_documents/07_08_application_supervision --warnings-as-errors`

Expected result: bootstrap starts `installed-agent`, and stopping the host
supervisor stops both the Jido instance and the Agent process.

## Important behavior

The host application owns its composition root. Jido remains one OTP
application with `Jido.Application` as the package composition root.

## Limits

This lesson starts one required resident Agent. Passive durable Agents should
activate from stable references when work arrives.

## Core Fit and Gaps

Jido child specifications and public Agent startup APIs compose with normal OTP
supervision. Bootstrap policy remains application code because each host has a
different set of required resident Agents.

## Files

- [Source](application_supervision.ex)
- [Tests](application_supervision_test.exs)

Previous: [Codec documents](../07_07_codec_documents/README.md)

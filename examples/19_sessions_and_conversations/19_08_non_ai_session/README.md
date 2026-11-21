# 19_08 Non-AI Session use

This lesson uses Session and Thread values as portable history for a support case.

## What you will learn

- Session and Thread are generic value-model contracts, not AI-only storage.
- The application owns event kinds and its public projection.

## Read the code

Read [the support case module](non_ai_session.ex) first.

## Run it

`mix test.examples examples/19_sessions_and_conversations/19_08_non_ai_session --warnings-as-errors`

Expected result: two support events remain ordered and survive Session encoding.

## Important behavior

Append returns a new Session. The source remains unchanged.

## Limits

This is an event history value, not an event store. It does not provide
concurrent writer control, subscriptions, or retention policy.

## Core Fit and Gaps

The generic Session and Thread contracts compose without AI APIs. Storage,
authorization, and event-schema evolution remain application concerns.

## Files

- [Source](non_ai_session.ex)
- [Tests](non_ai_session_test.exs)

[Previous: Persistence and restoration](../19_07_persistence_and_restoration/README.md)

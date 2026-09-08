> Subsystem review index. This document is pending approval.

# 12 — Errors and public contracts

Current comparison: [gap analysis](gap-analysis.md).

This cross-system seam owns defined errors, stable error codes, callback
normalization, safe projection, public shaped values, and portable-term rules.

Review [the error design](errors.md) against `lib/jido/error.ex` and
`lib/jido/portable_term.ex`.

Main alignment questions:

- Which public result positions can contain raw control values?
- Which errors have stable program codes?
- How are callback raises, exits, throws, and invalid returns normalized?
- Which public values must be Zoi-backed structs?
- Which values must satisfy the recursive portable-term contract?

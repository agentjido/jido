# Package matrix

This matrix identifies the dependencies selected by the Jido 3.0.0-beta.1
candidate. It does not claim that the unverified Bedrock profile passes.

## Core set

| Package | Version and source | Immutable identity | Status |
| --- | --- | --- | --- |
| `jido` | Hex `3.0.0-beta.1`; tag `v3.0.0-beta.1` on `release/v3` | Tagged commit `5413df1132859e702a62d48486caf2da61f499f3`; branch cut from `v3-spike` at `23ecf0fd` | Published 2026-09-14 with two recorded exceptions |
| `jido_action` | Hex `3.0.0-beta.11` | Registry checksum `97c60e158f81713d792c7631ed567673919f1a7d0f9024685863f9ac3fb71818` | Published source selected |
| `jido_signal` | Hex `3.0.0-beta.4` | Registry checksum `284d4f199b22b358906598ebfba734d37ea8a9404baed47939b94b50d837a05b`; source commit `1a62b1ddc306091cdcb7883ce63490f0f6ed2905` | Published source selected |

## Bedrock beta dependency set

`Jido.Persistence.Bedrock` is included in the beta package and its release
claim. It is optional for applications that do not use it. The current
candidate selects these published packages:

| Package | Version and source | Registry checksum | Status |
| --- | --- | --- | --- |
| `bedrock` | Hex `0.7.2` | `a08b779f65b42b159700f050ac76d4514fb9414aafa8a6305026e79fbf332959` | All real Bedrock service tests are skipped; prior strict-startup and snapshot failures remain unresolved |
| `bedrock_raft` | Hex `0.10.1` | `6cafdefd445917d1f717cdc09d8d6be3a98cd12fc791f45b62ca6704e89682da` | Selected by the tested Bedrock profile |

Local Bedrock commits `900ee439`, `905c567f`, and `8e97b5b8` are not in Hex
`0.7.2`. They are development work, not a publishable dependency source for
this Jido candidate. Recheck this matrix after a fixed Bedrock version is
published and selected.

The Jido production dependency tree has no path or Git source. Development and
test dependencies do not enter the package claim.

## Runtime matrix

| Role | Elixir | OTP | Required result |
| --- | --- | --- | --- |
| Declared package floor; beta.1 exception | 1.18.5 | 27.3.4.12 | Core suite not proven; test compilation fails on an example Directive. |
| Candidate runtime | 1.20.3 | 29.0.5 | Full local delivery gates pass. |

Jido declares Elixir `~> 1.18`. The tested floor and current runtime are the
evidence points. They do not claim every intermediate OTP patch.

## Packages outside this claim

Jido AI, Jido Browser, future transport packages, and future distributed
control-plane packages are not part of this matrix. Each owner must add its own
exact version set and compatibility tests before it claims V3 compatibility.

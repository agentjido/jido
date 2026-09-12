# Package matrix

This matrix defines the only V3 compatibility claim made by this local
candidate.

## Core set

| Package | Version and source | Immutable identity | Status |
| --- | --- | --- | --- |
| `jido` | `3.0.0-beta.1`; local Hex build from `v3-spike` | The commit that contains this record; parent `66c4d054` | Unpublished candidate |
| `jido_action` | Hex `3.0.0-beta.9` | Registry checksum `df9009a5870234be9de844dce161ea64a377598d8a197427fc1c8b14139dc6f9`; source tag `v3.0.0-beta.9` at `ac8331d7bf6b0378aa8d9ad862dddeefefde1308` | Published source selected |
| `jido_signal` | Hex `3.0.0-beta.4` | Registry checksum `284d4f199b22b358906598ebfba734d37ea8a9404baed47939b94b50d837a05b`; source commit `1a62b1ddc306091cdcb7883ce63490f0f6ed2905` | Published source selected |

The Jido production dependency tree has no path or Git source. Development and
test dependencies do not enter the package claim.

## Runtime matrix

| Role | Elixir | OTP | Required result |
| --- | --- | --- | --- |
| Support floor | 1.18.5 | 27.3.4.12 | Core suite passes. |
| Candidate runtime | 1.20.3 | 29.0.5 | Full local delivery gates pass. |

Jido declares Elixir `~> 1.18`. The tested floor and current runtime are the
evidence points. They do not claim every intermediate OTP patch.

## Packages outside this claim

Jido AI, Jido Browser, future transport packages, and future distributed
control-plane packages are not part of this matrix. Each owner must add its own
exact version set and compatibility tests before it claims V3 compatibility.

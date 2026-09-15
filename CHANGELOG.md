# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4-hatchify.2] - 2026-09-15

This release is published from the `hatchify/twilio_elixir` fork. It holds
release 0.1.4-hatchify.1 plus the change below. The fix is the one that
upstream pull request
[jeffhuen/twilio_elixir#7](https://github.com/jeffhuen/twilio_elixir/pull/7)
proposes for issue
[#6](https://github.com/jeffhuen/twilio_elixir/issues/6), taken unchanged so
that the fork carries no variant of it and the patch drops out when upstream
merges. The fork releases it because that pull request is open and the defect
stops every request.

### Fixed

- `Client.request/4` no longer raises `ArgumentError` on Finch 0.20 and later.
  The client passed `:receive_timeout` and `:pool_timeout` to `Finch.build/5`,
  whose options are `:unix_socket` and `:pool_tag` only. Finch validates them
  with `Keyword.validate!/2`, so every request raised
  `unknown keys [:pool_timeout, :receive_timeout]` rather than reaching the
  API. The two timeouts now go to `Finch.request/3`, which is what applies
  them.

### Added

- `Twilio.ClientFinchTest` performs one request over a real socket with no
  stub installed. Every other client test registers a stub with
  `Twilio.Test.stub/1` and therefore answers before Finch builds anything, so
  no test covered the Finch path. This one fails with the previous code and
  passes with the current code.

### Changed

- The lock file moves from Finch 0.21.0 to 0.23.0. The package requires
  `~> 0.19`, so a consumer is free to resolve a later Finch than the lock
  named, and the defect above appears only on the versions that validate
  build options. Testing against the current Finch is what reports it.


## [0.1.4-hatchify.1] - 2026-09-03

This release is published from the `hatchify/twilio_elixir` fork. It holds
upstream release 0.1.3 plus the fix below, which is proposed upstream.

### Fixed

- `Client.request/4` now encodes a list value as a repeated plain key
  (`StatusCallbackEvent=initiated&StatusCallbackEvent=ringing`) in form bodies
  and query strings, which is how the Twilio API and its official SDKs handle
  array parameters such as `StatusCallbackEvent` and `MediaUrl`. Previously a
  list encoded as a bracketed key (`StatusCallbackEvent[]=`), which Twilio
  ignores, so those parameters silently fell back to their defaults. A `nil`
  element of a list is now dropped instead of sent as an empty value.

## [0.1.3] - 2026-06-09

### Changed

- Updated Twilio OpenAPI specs from 2.6.7 to 2.6.9.
- Added generated services and resources for Conversations v2,
  Intelligence v3, Knowledge v2, Memory v1, and Voice v3 APIs.

### Fixed

- Service generator now merges caller-supplied `opts` into the
  `Client.request/4` call. Previously, generated service modules passed the
  caller's `opts` as a nested `opts:` key that `Client.request/4` never read,
  and hardcoded `base_url: "https://api.twilio.com"` so the caller's
  `:base_url` could not take effect. `Client.request/4` now also supports that
  legacy generated shape, so existing generated services honor caller-supplied
  `:base_url` (for local test simulators, sandbox/staging hosts, and
  self-hosted Twilio-compatible proxies), `:content_type`, and other request
  options without requiring regeneration. The explicit `params` argument
  continues to win over any `:params` key in `opts`.

## [0.1.2] - 2026-04-16

### Changed

- Updated Twilio OpenAPI specs from 2.6.4 to 2.6.7
- Added IAM v1 role permission service and resource
- Added Insights v2 voice report services/resources (account, inbound and
  outbound phone-number reports)
- Added Numbers v1 sender ID registration with embedded session support
- Added Messaging v3 typing indicator service
- Renamed `messaging.v1.service.us_app_to_person` object type to
  `..._response`
- Removed deprecated `flex.v1.instance` object type
- Miscellaneous field and parameter updates across Assistants, Flex, Studio,
  Verify, Video, TaskRouter, and other services

## [0.1.1] - 2026-03-03

### Changed

- Updated Twilio OpenAPI specs from 2.6.3 to 2.6.4
- Added `BundleSids` and `EndUserType` query params to bundle listing
- Added `Configuration` object param to video transcription updates
- Trimmed redundant inequality descriptions from call StartTime/EndTime params
- Updated messaging sender vertical enum with new categories
- Fixed Flex API path capitalization (`/v1/Instances`)
- Cleaned IAM Organizations `apiStandards` from placeholder to `v0.1`
- Added OAuth v2 session metadata schema and authorize fields

## [0.1.0] - 2026-03-03

### Added

#### API Coverage
- Auto-generated SDK from Twilio's 54 OpenAPI spec files (v2.6.3)
- 440+ service modules covering 37+ Twilio products (Messaging, Voice, Verify,
  Conversations, Flex, Insights, Video, and more)
- 420+ typed resource structs with automatic JSON-to-struct deserialization
- Object types registry mapping schema names to Elixir modules

#### Client & HTTP
- `Twilio.Client` with HTTP Basic auth (Account SID + Auth Token)
- Region and edge URL construction (e.g. `ie1`, `dublin`)
- Subaccount support via `:account_sid` option
- Connection pooling via Finch (auto-sized: `max(schedulers_online, 10)`)
- Request encoding: form-encoded for mutations, query params for reads
- Opt-in response metadata (`return_response: true`) exposing status,
  headers, and request ID

#### Retry & Resilience
- Unified retry covering 429, 5xx, and connection errors (opt-in, default: 0)
- `Retry-After` header parsing on 429 responses
- Exponential backoff with full jitter
- Idempotency token auto-generation (`I-Twilio-Idempotency-Token`) on
  retryable POST requests
- `Twilio.Error` typed error struct with `retryable?/1` helper

#### Pagination
- `Twilio.Page` with dual-format auto-detection:
  - v2010 flat format (`next_page_uri`)
  - v1/v2/v3 meta wrapper format (`meta.next_page_url`)
- `stream/1` for lazy auto-pagination via `Stream.unfold`

#### Webhooks
- `Twilio.Webhook` HMAC-SHA1 signature verification
- Form-encoded webhook validation (`valid?/4`)
- JSON body webhook validation (`valid_body?/4`)
- Constant-time comparison to prevent timing attacks

#### TwiML
- `Twilio.TwiML.VoiceResponse` — Say, Play, Gather, Dial, Record, Redirect,
  Hangup, Reject, Pause, Enqueue, plus nested nouns (Number, Client, Sip,
  Queue)
- `Twilio.TwiML.MessagingResponse` — Message (with Body/Media children),
  Redirect
- Automatic snake_case to camelCase attribute conversion
- XML escaping for text content and attribute values

#### Testing
- `Twilio.Test` per-process HTTP stubs via NimbleOwnership
- Full `async: true` support with process isolation
- `allow/1` for sharing stubs with child processes

#### Observability
- Structured `:telemetry` events: start, stop, exception, retry

#### Code Generation
- `mix twilio.generate` Mix task with `--clean`, `--dry-run`, `--stats`
- `scripts/sync_openapi.sh` for downloading specs from `twilio/twilio-oai`
- Auto-formatting of generated code

#### CI & Automation
- GitHub Actions CI: test matrix (Elixir 1.19-1.20, OTP 27-28), quality
  checks (Credo, format, Dialyzer), codegen determinism verification
- Weekly OpenAPI spec sync workflow with auto-PR generation
- `scripts/parity_report.sh` for endpoint coverage reporting

#### Documentation
- Guides: Getting Started, Webhooks, TwiML, Testing, Telemetry
- ExDoc with module grouping by category

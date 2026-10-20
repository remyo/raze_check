# Whole-manager capacity acceptance

**Status: pending.** The uninterrupted full baseline is still running; neither its complete target nor whole-archive assertions have passed yet.

The engineering target is **100 externally enrolled non-owner staff, plus the owner, and 10,000 genuine signed manager-received attendance events**. It is not a marketed capacity guarantee. Run from `packages/raze_check_local`:

```sh
RAZE_CAPACITY=1 caffeinate -i /absolute/flutter test --no-pub test/capacity_acceptance_test.dart --concurrency=1 --reporter=expanded
```

Ordinary package verification skips this explicitly labeled expensive test. It never counts a skip as capacity evidence. The fixture uses real SQLite/AES, actual invitation/approval and verify/import services, independent Ed25519 external signers, UUIDs and ordinary dated check-in/out bytes. The host key adapter is memory-backed; private synthetic manager keys are retained with private permissions in the owned temporary run directory for diagnostic reopening. This is not OS-key or 100-phone capture evidence. Smaller actual capture/native suites cover those separate paths.

The manager retains all invitation/grant/history/operation/result/journal/ownership/outbox/projection data. Main events await review; duplicate operations add real history. No subset archive, dropped operations, truncated payloads, fake tiny receipts or cap increase is allowed. The test reopens, retrieves every actual history page, checks same-operation replay and fresh-operation duplicates, inspects populated query plans and counts, exports the complete company, authenticates/inspects/applies it, and compares exact encoded logical archive content before activation. A passive restore is not authorization: the restored setup session is explicitly denied ordinary queries; representative real owner activation/query behavior is tested separately.

`metrics.json` records checkpoints at1/10/100/1000/5000/10000, phase wall times, actual counts, query plans, encrypted/compressed/expanded/entry bytes and host process peak RSS. Process RSS is not a phone memory limit; Dart/SQLite/crypto/ZIP/isolate allocations all matter. Crypto uses the real600,000-iteration KDF and whole-body AES implementation. Failure preserves the actual reached count/error, never relabels a sample as the target.

The archive caps remain encrypted/expanded64MiB, records.json sharing that total, other entries8MiB,10,000ZIP entries,524,288logical items and64MiB repeated raw payload expansion. Same-store capture+import or all10,000 reviewed histories have no fit guarantee. Source calculations are not measured passes. Actual results will be recorded after the complete run.

## Diagnostic instrumentation

The uninterrupted baseline binary records timings and RSS, without per-query counters. Its early1/10/100/1000 samples therefore do not prove SQL or AES counts. A diagnostic SQLite online-backup copy at a recorded committed count/revision preserves the original run and uses only its matching synthetic catalog/manager keys. A test-only QueryInterceptor and real PayloadCipher decorator record returned rows, returned binary-body bytes, maximum returned rows per statement, AES opens/sealed/plain bytes, maximum concurrent opens and whole-archive traversal. These are application-observable allocations/calls, not SQLite pages read, live Dart object-graph bytes or phone memory measurements.

`RAZE_CAPACITY_PROBE=/absolute/diagnostic-copy flutter test --no-pub test/capacity_probe_test.dart --concurrency=1 --reporter=expanded` runs from the local package. The probe enrolls one additional real external diagnostic signer because original remote signer seeds remain only in the uninterrupted process. It measures fresh verify/import, same-operation replay, new-operation duplicate, successive history pages and complete archive traversal. Every result names its baseline count/revision, extra signer/event, source manifest hash and capture method. It is neither an original early sample nor a second full10000-event run. Repeat the probe against the retained final10000-event store when available.

### Measured diagnostic checkpoint: 3,101 original events

[Raw synthetic measurements](capacity-probe-3101.json) capture revision3204 on2026-10-20. The diagnostic copy then adds one signer and one event. Baseline remains unchanged.

| Phase | Wall time | AES opens | Max concurrent opens | Returned sealed bytes | Largest SQL result |
| --- | ---: | ---: | ---: | ---: | ---: |
| Verify |99ms|308|102|105,694|102|
| Fresh import |565ms|3,715|3,101|1,835,271|3,101|
| Same-operation replay |221ms|615|102|212,526|102|
| New-operation duplicate |182ms|615|102|211,826|102|
| First history100 |51ms|303|1|167,093|100|
| Second history100 |55ms|303|1|167,080|100|
| Whole archive traversal |6.276s|19,439|1|19,068,335|32|

The fresh import opens exactly3,101 existing attendance projections; the measured maximum result/concurrent decrypt count exposes the current whole-projection duplicate check. No latency SLA or optimization is claimed. The diagnostic process peak RSS was250,675,200bytes. The counter called `sql.history` in this checkpoint groups `SELECT r.* FROM stored_rows r`, including archive traversal; phase names distinguish actual history reads from archive paging. SQL counts include repeated validation reads and are not unique-record counts. Query plans show the journal operation lookup searches by company, owner lookup scans its table, and history uses the company/id primary-key range.

Observed elapsed times include concurrent verification/native builds in an isolated source copy and other host load. They are run costs on this workstation, not isolated benchmarks or a phone latency SLA. The uninterrupted baseline is deliberately unoptimized.

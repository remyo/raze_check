# Whole-manager capacity acceptance

**Status: engineering fixture gate passed under the explicitly approved reconciliation scope.** The original test reached10,000 imports but failed its old replay-status expectation before export. Current-source full reopening/pages/report/duplicates/export/inspect/apply/exact-retention succeeded on an unfiltered independent copy. These are distinct evidence claims.

The engineering target is **100 externally enrolled non-owner staff, plus the owner, and 10,000 genuine signed manager-received attendance events**. It is not a marketed capacity guarantee. Run from `packages/raze_check_local`:

```sh
RAZE_CAPACITY=1 caffeinate -i /absolute/flutter test --no-pub test/capacity_acceptance_test.dart --concurrency=1 --reporter=expanded
```

Ordinary package verification skips this explicitly labeled expensive test. It never counts a skip as capacity evidence. The fixture uses real SQLite/AES, actual invitation/approval and verify/import services, independent Ed25519 external signers, UUIDs and ordinary dated check-in/out bytes. The host key adapter is memory-backed; private synthetic manager keys are retained with private permissions in the owned temporary run directory for diagnostic reopening. This is not OS-key or 100-phone capture evidence. Smaller actual capture/native suites cover those separate paths.

The manager retains all invitation/grant/history/operation/result/journal/ownership/outbox/projection data. Main events await review; duplicate operations add real history. No subset archive, dropped operations, truncated payloads, fake tiny receipts or cap increase is allowed. The test reopens, retrieves every actual history page, checks same-operation replay and fresh-operation duplicates, inspects populated query plans and counts, exports the complete company, authenticates/inspects/applies it, and compares exact encoded logical archive content before activation. A passive restore is not authorization: the restored setup session is explicitly denied ordinary queries; representative real owner activation/query behavior is tested separately.

`metrics.json` records checkpoints at1/10/100/1000/5000/10000, phase wall times, actual counts, query plans, encrypted/compressed/expanded/entry bytes and host process peak RSS. Process RSS is not a phone memory limit; Dart/SQLite/crypto/ZIP/isolate allocations all matter. Crypto uses the real600,000-iteration KDF and whole-body AES implementation. Failure preserves the actual reached count/error, never relabels a sample as the target.

The archive caps remain encrypted/expanded64MiB, records.json sharing that total, other entries8MiB,10,000ZIP entries,524,288logical items and64MiB repeated raw payload expansion. Same-store capture+import or all10,000 reviewed histories have no fit guarantee. Source calculations are not measured passes. Actual full-fixture results are recorded below.

## Diagnostic instrumentation

The uninterrupted baseline binary records timings and RSS, without per-query counters. Its early1/10/100/1000 samples therefore do not prove SQL or AES counts. A diagnostic SQLite online-backup copy at a recorded committed count/revision preserves the original run and uses only its matching synthetic catalog/manager keys. A test-only QueryInterceptor and real PayloadCipher decorator record returned rows, returned binary-body bytes, maximum returned rows per statement, AES opens/sealed/plain bytes, maximum concurrent opens and whole-archive traversal. These are application-observable allocations/calls, not SQLite pages read, live Dart object-graph bytes or phone memory measurements.

`RAZE_CAPACITY_PROBE=/absolute/diagnostic-copy flutter test --no-pub test/capacity_probe_test.dart --concurrency=1 --reporter=expanded` runs from the local package. The probe enrolls one additional real external diagnostic signer because original remote signer seeds were process-only and are not retained. It measures fresh verify/import, same-operation replay, new-operation duplicate, successive history pages and complete archive traversal. Every result names its baseline count/revision, extra signer/events, source manifest hash and capture method. It is neither an original early sample nor a second full10000-event run. The retained5121-event and final10000-event snapshots were both measured with the current instrumentation below.

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

The fresh import opens exactly3,101 existing attendance projections; the measured maximum result/concurrent decrypt count exposes that original-source whole-projection duplicate check. No latency SLA or optimization is claimed. The diagnostic process peak RSS was250,675,200bytes. The counter called `sql.history` in this checkpoint groups `SELECT r.* FROM stored_rows r`, including archive traversal; phase names distinguish actual history reads from archive paging. SQL counts include repeated validation reads and are not unique-record counts. Query plans show the journal operation lookup searches by company, owner lookup scans its table, and history uses the company/id primary-key range.

Observed elapsed times include concurrent verification/native builds in an isolated source copy and other host load. They are run costs on this workstation, not isolated benchmarks or a phone latency SLA. The uninterrupted baseline is deliberately unoptimized.

## Completed original imports and current whole-archive reconciliation

The original sourceBASE186ab54 enrolled100external non-owner staff and imported10,000real signed receipts in11,894.263s (~3h18m14s). It then reopened/read101history pages and failed the test assertion expecting `received` for the same operation; the existing service correctly returned `alreadyReceived`. Exit1 and [terminal metrics](capacity-original-10000.json) are retained. A post-termination immutable read independently confirmed10,000stored attendance rows and10,000complete oracle lines. The original did not execute its archive phase and is not relabeled passed. Observed verify/import totals were2,659.698s/9,200.774s; host pressure and concurrent other work substantially confound timing.

Controller Ruling47 explicitly permits current-source reconciliation of this genuine historical corpus rather than a second initial10,000-import run. [Current full results](capacity-current-10000.json), source33dd2b9 plus the recorded Task13 harness manifest, passed in3m59s. The current service reopened the full101-staff store, compared every original receipt byte using a clearly privileged storage oracle, traversed all101management history pages (max100output rows), compared all10,000full-report rows, and retained exact original acknowledgment bytes for same/new-operation duplicates. Management queries remain authorized APIs; the owner never impersonates staff or uses their personal receipt API as a bulk read.

The current whole CompanyScope archive includes121,224logical items and all setup, signed messages, operation results, journals, associations and projections. It was authenticated, inspected and applied to a new passive store; the complete encoded logical records hash matches before/after. Passive management and personal receipt access are denied. Actual600,000-iteration KDF, unchanged caps and real encryption were used.

| Measurement | Actual |
| --- | ---: |
| Encrypted archive |19,276,931bytes|
| Compressed payload |19,276,863bytes|
| Expanded total |65,012,197bytes|
| records.json |65,010,879bytes|
| Remaining64MiB expanded headroom |2,096,667bytes (~3.1%)|
| Peak host process RSS across reconciliation |1,113,128,960bytes|
| Whole archive create/share |52.45s|
| Whole archive inspect |18.55s|
| Whole archive apply |51.64s|

This narrow headroom does not establish that10,000reviewed events, additional history, attachments, or combined capture/import records fit. Exceeding a format limit must reject safely; no history or cap was changed. Whole-buffer archive/crypto processing has substantial host memory cost; this10,000-event archive was not exercised on a phone. The current full report intentionally materializes10,000output rows; bounded SQL reads are not a claim that its whole output is page-sized. The recorded SQL/AES counters measure actual returned binary bytes, maximum SQL results, concurrent decrypts and in-flight sealed bytes. They do not measure SQLite scanned rows or the entire live Dart heap.

Exact original closed data, pristine consistent snapshot, diagnostic copies, full encrypted archive, matching private synthetic keys, receipt oracle and source/command manifests are retained in ignored `.superpowers/evidence/2026-10-19-raze-check-foundation/`. Private material is not committed. Managed-worktree cleanup must preserve these ignored artifacts.

## Current-source fresh import probes at5,121 and10,000 events

Both [5,121-event](capacity-probe-5121.json) and [10,000-event](capacity-probe-10000.json) diagnostic runs passed. Each starts from its own unfiltered historical snapshot, adds one independently enrolled external signer and three genuine signed events, and ends at5,124/10,003events respectively. They verify first-checkout review hints, resolution after a late earlier check-in, separated repeated-check-in hints, exact immutable bytes and original acknowledgments on both replay paths. These are actual new derivations, not duplicate replay presented as import work; they do not claim the original10,000projections were generated by the repaired importer.

| Phase/observable |5,121 baseline |10,000 baseline |
| --- | ---: | ---: |
| First fresh import |0.720s|1.267s|
| Late earlier endpoint import |0.756s|1.226s|
| Repeated check-in import |0.667s|1.244s|
| First history100 |0.041s|0.038s|
| Whole logical archive traversal |11.369s|30.285s|
| Fresh import AES opens |5,735|10,614|
| Fresh import max concurrent AES opens |5,121|10,000|
| Fresh import max SQL binary result / concurrent sealed bytes |2,683,325bytes|5,240,000bytes|
| Fresh import maximum SQL returned rows |5,121|10,000|
| History100 maximum SQL returned rows |100|100|
| Diagnostic peak host process RSS |317,472,768bytes|404,471,808bytes|

Current import still materializes the full company projection set and starts many concurrent decrypts; the actual costs remain a documented scaling limitation. History100 returned at most100rows with sequential AES opens; whole archive traversal returned at most32rows per SQL result with sequential opens, while complete encoded archives/reports still materialize their full output. All detailed summed bytes, maximum binary results, individual plaintext and in-flight sealed-byte metrics plus populated query plans are retained in the linked JSON. No source-derived estimate is labeled a measured sample. Early1/10/100/1000timing-only observations remain uninstrumented; the earlier3,101probe retains its original source and narrower counters.

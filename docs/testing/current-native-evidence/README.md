# Current-source native checks

Production source33dd2b9 is unchanged between these Android artifacts. The first full foundation suite passed its six existing behavior cases and the new overnight, SQL rollback, and handover cases, but the new delayed-callback harness asserted too early. Its failed result is preserved. The corrected matrix explicitly waits until database authorization has opened the injected picker; all four matrix cases then passed. Framework teardown is listed separately from behavior tests.

Both builds ran on Samsung SM-S931Q, Android16/API36,2026-10-20, with real namespaced OS keys and SQLite. Prior installed APK ownership was checked by its exact hash; the same Android signing certificate was verified before replacing it. `flutter drive --no-pub --debug --use-application-binary=<exact retained APK> --target=<recorded entrypoint> --driver=<explicit integration driver> --test-arguments=--packages=<isolated copy package_config.json> --device-id=<selected physical device> --keep-app-running` retained the synthetic app data.

The four additional cases prove:

- Original UTC/claimed offset and corrected UTC/effective offset persist; actual Flutter detail text and Tokyo midnight dashboard/report dates agree after reopen.
- A delayed callback cannot import into a newly selected company; null callback produces no import; five minutes of actual injected idle-clock advance rejects completion and invokes the locked flow. This is an application callback test, not native picker interaction.
- An injected SQLite transaction abort leaves no event/outbox and preserves the retry draft; the same operation commits one exact retained receipt after reopen. This is not a full-disk or physical-power-loss experiment.
- A saved handover offer survives graceful reopen, the source remains frozen when acknowledgment is withheld, the target recovers the exact acknowledgment after reopen, and it can capture a fresh punch without losing old event/intent bytes. This is not an OS kill during handover.

Earlier [clean-install evidence](../lifecycle-evidence/) separately establishes external host custody of the actual exported archives and same-byte restore after uninstall on both platforms; a same-app sandbox file alone is not external custody. The user explicitly deferred current-source iPhone signing/testing after the selected-team account/profile gap; prior iPhone artifacts retain their original signer/source provenance.

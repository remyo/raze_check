# Synthetic physical process evidence

The JSON pre/post/result files are from actual owned synthetic app installations. Results bind platform, exact test artifact hash, operation/event IDs and SHA256 of original signed bytes. The interrupted first driver is not a test pass; the host comparator validates independently collected post artifacts after OS termination and same-install relaunch.

`android-visible.png` and `ios-visible.png` renders the actual saved receipt and QR in the acceptance harness with synthetic data and the default test theme. These are not the normal branded dashboard. The accepted normal full-shell widget captures are in `../screenshots/`.

Android before/committed/visible cases passed. iPhone before/committed/visible cases passed; the before case’s first debugger attempts are retained in private diagnostics. The original SIGKILL stopped in Flutter LLDB; closing only the owned driver/debugger allowed the old PID to disappear. A failed early continue and failed attach were retained. The successful same-install fresh process waited for its exact SIGSTOP attachment before one continue and produced the verified post artifact. These cases use independent logical stores on the recorded phone; the two-phone printed-camera gate remains deferred by the user.

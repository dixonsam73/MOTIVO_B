# Independent Phase 6 evidence

All fixtures are synthetic. No production, device or personal data was tested.
Sources are the exact final probe sources executed. Do not regenerate from an earlier draft harness.
The report describes every substitution and the distinction between a source proof and runtime evidence.

To rerun, compile each source pair using `swiftc -module-cache-path /private/tmp/etudes-phase6-audit/swift-cache -parse-as-library <pair> -o /private/tmp/etudes-phase6-audit/<name>` and run the executable. Create `/private/tmp/etudes-phase6-audit` first. These probes use hardcoded disposable paths under that directory. Do not point them at app data.

Pairs: Queue.swift + QueueProbe.swift; SavedList.swift + ListProbe.swift; Coordinator.swift + CoordinatorProbe.swift; CommitProbe.swift + ProbeStaging.swift.

Queue probe restores fixture directory permissions after its deliberate write denial. List and commit metadata use dedicated defaults suites. The commit model is a minimal in-memory model, not a migrated user store. The attestation service and queue transport are stubs, not Apple or Supabase.

Release build used isolated derived data and a copied existing dependency cache; package updates were disabled. Release build log records two architectures. The C-14 result is the existing scoped source discriminator.

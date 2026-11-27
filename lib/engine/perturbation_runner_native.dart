import 'dart:isolate';

/// Runs a synchronous perturbation computation on a background isolate.
Future<T> runPerturbationTask<T>(T Function() computation) =>
    Isolate.run(computation);

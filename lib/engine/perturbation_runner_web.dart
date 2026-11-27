/// Runs a synchronous perturbation computation asynchronously on web platforms.
Future<T> runPerturbationTask<T>(T Function() computation) =>
    Future<T>.delayed(Duration.zero, computation);

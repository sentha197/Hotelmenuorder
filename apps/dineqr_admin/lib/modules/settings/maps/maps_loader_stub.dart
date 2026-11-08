/// Android: the key is in the manifest (build.gradle.kts), so the map is
/// ready.
Future<bool> ensureGoogleMapsLoaded(String apiKey) async => apiKey.isNotEmpty;

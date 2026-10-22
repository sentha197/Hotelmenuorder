/// Where bundled demo media lives.
///
/// Menu data refers to photos as `assets/images/<name>.jpg`, the same paths
/// stored on devices before the apps were split. The files are bundled with
/// this package, so widgets load them with [packageFor]. A backend can send
/// full `https://` URLs instead (see [isNetwork]).
abstract final class DineQrAssets {
  static const package = 'dineqr_core';

  static const _bundledPrefix = 'assets/images/';

  static bool isNetwork(String path) =>
      path.startsWith('https://') || path.startsWith('http://');

  /// The package that bundles [path], or null for app assets.
  static String? packageFor(String path) =>
      path.startsWith(_bundledPrefix) ? package : null;
}

// Makes Google Maps usable on this platform (loads the Maps JavaScript API
// on the web; nothing to do on Android).
export 'maps_loader_stub.dart'
    if (dart.library.js_interop) 'maps_loader_web.dart';

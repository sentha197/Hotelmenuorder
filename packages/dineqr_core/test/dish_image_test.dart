import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A buffer starting with [signature], padded so length checks pass.
List<int> file(List<int> signature) => [
  ...signature,
  ...List.filled(32, 0),
];

/// An ISO base media `ftyp` box with [brand] as its major brand.
List<int> ftyp(String brand) => [
  0, 0, 0, 0x18, ...'ftyp'.codeUnits, ...brand.codeUnits, //
  ...List.filled(16, 0),
];

void main() {
  group('DishImageUploader.extensionFor', () {
    test('names JPEG, PNG and WebP by their leading bytes', () {
      expect(
        DishImageUploader.extensionFor(file([0xFF, 0xD8, 0xFF, 0xE0])),
        'jpg',
      );
      expect(
        DishImageUploader.extensionFor(
          file([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        'png',
      );
      expect(
        DishImageUploader.extensionFor([
          0x52, 0x49, 0x46, 0x46, // RIFF
          0x00, 0x00, 0x00, 0x00, // size
          0x57, 0x45, 0x42, 0x50, // WEBP
          ...List.filled(16, 0),
        ]),
        'webp',
      );
    });

    test('also names the other formats the server converts', () {
      expect(DishImageUploader.extensionFor(file('GIF89a'.codeUnits)), 'gif');
      expect(DishImageUploader.extensionFor(file('BM'.codeUnits)), 'bmp');
      expect(
        DishImageUploader.extensionFor(file([0x49, 0x49, 0x2A, 0x00])),
        'tif',
      );
      expect(
        DishImageUploader.extensionFor(file([0x00, 0x00, 0x01, 0x00])),
        'ico',
      );
      expect(DishImageUploader.extensionFor(ftyp('avif')), 'avif');
      expect(DishImageUploader.extensionFor(ftyp('avis')), 'avif');
      expect(DishImageUploader.extensionFor(ftyp('heic')), 'heic');
      expect(DishImageUploader.extensionFor(ftyp('mif1')), 'heic');
    });

    test('gives no name to anything unknown, which is not a refusal', () {
      // The app only uses the name for the upload; the server decides.
      expect(
        DishImageUploader.extensionFor(file([0x25, 0x50, 0x44, 0x46])),
        isNull,
      );
      expect(DishImageUploader.extensionFor('hello'.codeUnits), isNull);
      expect(DishImageUploader.extensionFor(ftyp('isom')), isNull);
    });

    test('does not name a RIFF container that is not WebP', () {
      // A .wav file is also RIFF; only the WEBP tag at offset 8 counts.
      expect(
        DishImageUploader.extensionFor([
          0x52, 0x49, 0x46, 0x46,
          0x00, 0x00, 0x00, 0x00,
          0x57, 0x41, 0x56, 0x45, // WAVE
          ...List.filled(16, 0),
        ]),
        isNull,
      );
    });

    test('does not read past the end of a short buffer', () {
      for (var length = 0; length < 12; length++) {
        expect(
          () => DishImageUploader.extensionFor(
            List.filled(length, 0x52), // a truncated "RIFF..."
          ),
          returnsNormally,
          reason: 'length $length',
        );
      }
      // A JPEG signature is only 3 bytes, so it is still recognised.
      expect(DishImageUploader.extensionFor([0xFF, 0xD8, 0xFF]), 'jpg');
    });
  });

  group('uploading a photo', () {
    test('any format reaches the server, which alone decides', () async {
      final sent = <String>[];
      final store = MemoryStore();
      final catalog = CatalogController(
        _RecordingUploader(sent, store),
        store,
        guard: const _AllowAll(),
      );
      // An AVIF, a HEIC and something unknown all go up unjudged.
      await catalog.uploadDishPhoto(ftyp('avif'));
      await catalog.uploadDishPhoto(ftyp('heic'));
      await catalog.uploadDishPhoto('not a photo'.codeUnits);
      expect(sent, ['dish.avif', 'dish.heic', 'dish.img']);
    });

    test('a file over the size limit is still refused up front', () {
      final store = MemoryStore();
      final catalog = CatalogController(
        _RecordingUploader([], store),
        store,
        guard: const _AllowAll(),
      );
      expect(
        () => catalog.uploadDishPhoto(
          List.filled(DishImageUploader.maxBytes + 1, 0),
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });
}

class _AllowAll implements AccessGuard {
  const _AllowAll();

  @override
  StaffAccount? get actor => null;

  @override
  bool can(Permission permission) => true;

  @override
  void require(Permission permission) {}
}

/// A menu repository that can store photos and remembers the file names it
/// was given.
class _RecordingUploader extends DemoMenuRepository
    implements DishImageUploader {
  _RecordingUploader(this.names, MemoryStore store)
    : super(latency: Duration.zero, store: store);

  final List<String> names;

  @override
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async {
    names.add(filename);
    return 'https://example.test/$filename';
  }
}

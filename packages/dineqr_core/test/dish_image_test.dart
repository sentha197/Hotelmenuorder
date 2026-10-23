import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A buffer starting with [signature], padded so length checks pass.
List<int> file(List<int> signature) => [
  ...signature,
  ...List.filled(32, 0),
];

void main() {
  group('DishImageUploader.extensionFor', () {
    test('recognises JPEG, PNG and WebP by their leading bytes', () {
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

    test('rejects formats the backend does not accept', () {
      // GIF, PDF and a bare text file.
      expect(
        DishImageUploader.extensionFor(file([0x47, 0x49, 0x46, 0x38])),
        isNull,
      );
      expect(
        DishImageUploader.extensionFor(file([0x25, 0x50, 0x44, 0x46])),
        isNull,
      );
      expect(DishImageUploader.extensionFor('hello'.codeUnits), isNull);
    });

    test('rejects a RIFF container that is not WebP', () {
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
}

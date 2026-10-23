// Exports the menu, categories, default settings, offers and tables that the
// offline demo used to hard-code, as the backend's initial catalogue:
//
//     cd packages/dineqr_core
//     flutter test tool/export_seed_test.dart
//
// The backend imports the file once (idempotently) into PostgreSQL; the apps
// then read this data from the API. Sample orders, bills, payments, staff and
// inventory are deliberately not exported.
import 'dart:convert';
import 'dart:io';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export the initial catalogue for the backend seed', () async {
    final settings = const RestaurantSettings();
    final tables = await LocalSettingsRepository(MemoryStore()).fetchTables();
    final catalogue = {
      'source': 'packages/dineqr_core (former offline demo data)',
      'categories': [for (final c in MenuCategory.defaults) c.toJson()],
      'items': [for (final item in demoMenuItems) item.toJson()],
      // Time zone is chosen at setup; the other defaults match the demo.
      'settings': settings.toJson()..remove('utcOffset'),
      'tables': [for (final t in tables) t.toJson()],
    };
    final out = File(
      '../../backend/src/DineQR.Api/Data/Seed/initial-catalog.json',
    );
    await out.parent.create(recursive: true);
    await out.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(catalogue)}\n',
    );
    expect(catalogue['items'], isNotEmpty);
  });
}

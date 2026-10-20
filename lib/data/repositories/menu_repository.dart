import '../demo/demo_menu_data.dart';
import '../models/menu_item.dart';

/// Source of the restaurant menu. Swap [DemoMenuRepository] for an API-backed
/// implementation without touching the UI.
abstract interface class MenuRepository {
  Future<List<MenuItem>> fetchMenu();
}

class DemoMenuRepository implements MenuRepository {
  const DemoMenuRepository({
    this.latency = const Duration(milliseconds: 450),
    this.items = demoMenuItems,
  });

  /// Simulated network delay so loading states are visible in the demo.
  final Duration latency;
  final List<MenuItem> items;

  @override
  Future<List<MenuItem>> fetchMenu() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return List.unmodifiable(items);
  }
}

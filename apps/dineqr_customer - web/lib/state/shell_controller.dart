import 'package:flutter/foundation.dart';

enum ShellTab { home, menu, cart, orders, more }

/// Selected bottom-navigation tab of the main shell.
class ShellController extends ChangeNotifier {
  ShellTab _current = ShellTab.home;
  int? _pendingOrdersTab;

  ShellTab get current => _current;

  /// Shows [tab]. [ordersTab] asks the orders screen to open a specific
  /// sub-tab (0 = current, 1 = past), e.g. after placing an order.
  void select(ShellTab tab, {int? ordersTab}) {
    _current = tab;
    if (ordersTab != null) _pendingOrdersTab = ordersTab;
    notifyListeners();
  }

  /// Returns and clears the pending orders sub-tab request.
  int? takePendingOrdersTab() {
    final value = _pendingOrdersTab;
    _pendingOrdersTab = null;
    return value;
  }
}

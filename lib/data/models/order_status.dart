/// Kitchen workflow for an order. Orders only move forward one step at a time.
enum OrderStatus {
  placed('Order Placed', 'Placed'),
  preparing('Preparing in Kitchen', 'Preparing'),
  readyToServe('Ready to Serve', 'Ready'),
  served('Served at Table', 'Served');

  const OrderStatus(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  OrderStatus? get next => index < OrderStatus.values.length - 1
      ? OrderStatus.values[index + 1]
      : null;

  /// Still in progress (shown under "Current Orders").
  bool get isActive => this != OrderStatus.served;

  bool canTransitionTo(OrderStatus target) => target.index == index + 1;

  static OrderStatus parse(String? name) => OrderStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => OrderStatus.placed,
  );
}

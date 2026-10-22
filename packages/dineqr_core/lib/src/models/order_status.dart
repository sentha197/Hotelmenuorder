/// Kitchen workflow for an order. Orders move forward one step at a time and
/// can be cancelled until they are ready to serve.
enum OrderStatus {
  placed('Order Placed', 'Placed'),
  accepted('Accepted by Kitchen', 'Accepted'),
  preparing('Preparing in Kitchen', 'Preparing'),
  readyToServe('Ready to Serve', 'Ready'),
  served('Served at Table', 'Served'),
  cancelled('Cancelled', 'Cancelled');

  const OrderStatus(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  /// The forward workflow, without [cancelled].
  static const flow = [placed, accepted, preparing, readyToServe, served];

  /// The four stages shown to guests. [accepted] is shown as part of
  /// [placed] ("accepted by the kitchen").
  static const customerStages = [placed, preparing, readyToServe, served];

  OrderStatus? get next {
    final index = flow.indexOf(this);
    if (index == -1 || index == flow.length - 1) return null;
    return flow[index + 1];
  }

  /// Still in progress (shown under "Current Orders").
  bool get isActive => this != served && this != cancelled;

  bool get isFinal => !isActive;

  /// Restaurant policy: an order can be cancelled until it is ready.
  bool get canCancel => this == placed || this == accepted || this == preparing;

  /// The guest-facing stage this status belongs to.
  OrderStatus get customerStage => this == accepted ? placed : this;

  bool canTransitionTo(OrderStatus target) =>
      target == next || (target == cancelled && canCancel);

  static OrderStatus parse(String? name) => OrderStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => OrderStatus.placed,
  );
}

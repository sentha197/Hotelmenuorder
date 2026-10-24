/// How an order is collected.
///
/// Both modes are the same order with the same pricing and kitchen flow; the
/// only difference is whether a table is involved. An order carries its type
/// in its table number rather than a separate field, so one list of orders
/// serves both (see [OrderTables]).
enum OrderType {
  dineIn('Dine-in', 'Eating in at a table'),
  takeaway('Takeaway', 'Collected at the counter');

  const OrderType(this.label, this.description);

  final String label;
  final String description;

  bool get isTakeaway => this == OrderType.takeaway;
}

abstract final class OrderTables {
  /// Table number of a takeaway order. Real tables start at 1, so zero is
  /// free to mean "no table". Kept in step with `OrderTables.Takeaway` on
  /// the server.
  static const takeaway = 0;

  static bool isTakeaway(int table) => table == takeaway;

  static OrderType typeOf(int table) =>
      isTakeaway(table) ? OrderType.takeaway : OrderType.dineIn;

  /// How the table is shown on tickets, bills and order lists: `Table 07`
  /// or `Takeaway`.
  static String label(int table) => isTakeaway(table)
      ? 'Takeaway'
      : 'Table ${table.toString().padLeft(2, '0')}';

  /// For places already headed "Table" (report columns, badges): `07`, or
  /// `Takeaway`.
  static String shortLabel(int table) =>
      isTakeaway(table) ? 'Takeaway' : table.toString().padLeft(2, '0');
}

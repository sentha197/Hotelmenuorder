/// How an order is collected.
///
/// Both modes are the same order with the same pricing and kitchen flow; the
/// only difference is whether a table is involved. An order carries its type
/// in its table number rather than a separate field, so one list of orders
/// serves both (see [OrderTables]).
enum OrderType {
  dineIn('Dine-in', 'Eating in at a table'),
  parcel('Parcel', 'Collected at the counter');

  const OrderType(this.label, this.description);

  final String label;
  final String description;

  bool get isParcel => this == OrderType.parcel;
}

abstract final class OrderTables {
  /// Table number of a parcel order. Real tables start at 1, so zero is free
  /// to mean "no table". Kept in step with `OrderTables.Parcel` on the server.
  static const parcel = 0;

  static bool isParcel(int table) => table == parcel;

  static OrderType typeOf(int table) =>
      isParcel(table) ? OrderType.parcel : OrderType.dineIn;

  /// How the table is shown on tickets, bills and order lists.
  static String label(int table) =>
      isParcel(table) ? 'Parcel' : 'Table ${table.toString().padLeft(2, '0')}';

  /// The short form used where space is tight, e.g. a kitchen ticket badge.
  static String shortLabel(int table) =>
      isParcel(table) ? 'PCL' : table.toString().padLeft(2, '0');
}

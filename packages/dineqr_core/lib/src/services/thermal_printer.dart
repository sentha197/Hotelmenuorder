import 'dart:typed_data';

import '../models/billing.dart';
import '../utils/currency.dart';
import '../utils/formatters.dart';

/// A receipt printer reached over Bluetooth or the network. Implement this
/// with a transport plugin for the printer model the restaurant uses.
abstract interface class ThermalPrinter {
  /// False until a printer is paired and connected.
  bool get isAvailable;

  /// e.g. "No thermal printer connected".
  String get description;

  /// Sends raw ESC/POS bytes (see [EscPosReceipt]).
  Future<void> printBytes(Uint8List bytes);
}

/// Default: no printer configured. Printing goes through the system print
/// dialog (PDF) instead; nothing claims a physical print happened.
class UnavailableThermalPrinter implements ThermalPrinter {
  const UnavailableThermalPrinter();

  @override
  bool get isAvailable => false;

  @override
  String get description => 'No thermal printer connected';

  @override
  Future<void> printBytes(Uint8List bytes) =>
      Future.error(StateError('No thermal printer is connected.'));
}

/// Encodes a bill as ESC/POS commands for 58 mm (32 columns) or 80 mm
/// (48 columns) printers. ASCII only: the rupee sign is written as "Rs."
/// because most printer code pages do not include it.
abstract final class EscPosReceipt {
  static const _esc = 0x1B;
  static const _gs = 0x1D;

  static Uint8List encode(Invoice invoice, {int columns = 32}) {
    final out = BytesBuilder();
    void command(List<int> bytes) => out.add(bytes);
    void text(String value) => out.add(_ascii(value));
    void line([String value = '']) => text('$value\n');
    void align(int mode) => command([_esc, 0x61, mode]); // 0 left, 1 centre
    void bold(bool on) => command([_esc, 0x45, on ? 1 : 0]);
    void size(int mode) => command([_gs, 0x21, mode]); // 0x11 = double
    String money(Money m) => CurrencyFormatter.format(m).replaceAll('₹', 'Rs.');
    String pair(String left, String right) {
      final space = columns - right.length;
      final l = left.length >= space ? left.substring(0, space - 1) : left;
      return '${l.padRight(space)}$right';
    }

    command([_esc, 0x40]); // initialise
    align(1);
    bold(true);
    size(0x11);
    line(invoice.restaurant.name.toUpperCase());
    size(0);
    bold(false);
    final r = invoice.restaurant;
    if (r.address.isNotEmpty) line(r.address);
    if (r.phone.isNotEmpty) line(r.phone);
    if (r.taxRegistration.isNotEmpty) line('Tax reg: ${r.taxRegistration}');
    line(invoice.status == InvoiceStatus.paid ? 'RECEIPT' : 'BILL');
    align(0);
    line('-' * columns);
    line(pair('Bill', invoice.billNumber));
    line(pair('Order', invoice.orderId));
    line(
      invoice.isTakeaway
          ? pair('Type', 'TAKEAWAY')
          : pair('Table', AppFormat.table(invoice.tableNumber)),
    );
    line(pair('Date', AppFormat.dateTime(invoice.createdAt)));
    line('-' * columns);
    for (final item in invoice.lines) {
      line(pair('${item.quantity} x ${item.name}', money(item.lineTotal)));
      for (final option in item.options) {
        line('   $option');
      }
    }
    line('-' * columns);
    final a = invoice.amounts;
    line(pair('Subtotal', money(a.subtotal)));
    if (a.hasDiscount) line(pair('Discount', '-${money(a.discount)}'));
    if (a.hasServiceCharge) {
      line(pair('Service charge', money(a.serviceCharge)));
    }
    line(pair(a.taxLabel, money(a.tax)));
    bold(true);
    line(pair('TOTAL', money(a.total)));
    bold(false);
    line(pair('Paid', money(invoice.amountPaid)));
    if (!invoice.amountRefunded.isZero) {
      line(pair('Refunded', '-${money(invoice.amountRefunded)}'));
    }
    line(pair('Balance', money(invoice.outstanding)));
    for (final p in invoice.payments) {
      if (p.status != PaymentStatus.succeeded) continue;
      line(pair(p.method.label, money(p.amount)));
      if (p.reference.isNotEmpty) line('  Ref ${p.reference}');
    }
    if (invoice.isSimulated || invoice.isDemoSample) {
      line('-' * columns);
      align(1);
      line('DEMO - simulated payment');
      line('No money was charged.');
      align(0);
    }
    line('-' * columns);
    align(1);
    if (r.footer.isNotEmpty) line(r.footer);
    line('Powered by DineQR');
    command([0x0A, 0x0A, 0x0A]);
    command([_gs, 0x56, 0x42, 0x00]); // feed and partial cut
    return out.toBytes();
  }

  /// Printable ASCII only; other characters become `?`.
  static List<int> _ascii(String value) => [
    for (final unit in value.codeUnits)
      unit == 0x0A || (unit >= 0x20 && unit < 0x7F) ? unit : 0x3F,
  ];
}

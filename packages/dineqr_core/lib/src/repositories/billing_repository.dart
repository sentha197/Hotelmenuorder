import '../models/billing.dart';
import '../storage/key_value_store.dart';

/// Bills with their payments and refunds. In production this is the
/// restaurant backend, which must calculate totals server-side and only
/// record payments its payment provider has verified.
abstract interface class BillingRepository {
  Future<List<Invoice>> fetchInvoices();

  /// Creates or replaces a bill.
  Future<void> saveInvoice(Invoice invoice);

  Future<void> replaceAll(List<Invoice> invoices);
}

class LocalBillingRepository implements BillingRepository {
  LocalBillingRepository(KeyValueStore store, {this.seed = const []})
    : _list = JsonListStore(
        store,
        StorageKeys.invoices,
        Invoice.fromJson,
        (i) => i.toJson(),
      );

  final JsonListStore<Invoice> _list;

  /// Bills for a fresh install (matching the seeded orders).
  final List<Invoice> seed;

  List<Invoice>? _invoices;

  List<Invoice> get _all => _invoices ??= _list.read() ?? [...seed];

  @override
  Future<List<Invoice>> fetchInvoices() async => List.unmodifiable(_all);

  @override
  Future<void> saveInvoice(Invoice invoice) async {
    final exists = _all.any((i) => i.id == invoice.id);
    _invoices = exists
        ? [for (final i in _all) i.id == invoice.id ? invoice : i]
        : [..._all, invoice];
    await _list.write(_invoices!);
  }

  @override
  Future<void> replaceAll(List<Invoice> invoices) async {
    _invoices = [...invoices];
    await _list.write(_invoices!);
  }
}

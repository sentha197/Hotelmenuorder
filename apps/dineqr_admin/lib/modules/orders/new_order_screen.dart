import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../widgets/admin_widgets.dart';
import 'admin_order_detail_screen.dart';

/// Staff order entry for a table (e.g. a guest without a phone). Dishes use
/// their default options.
class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key, this.initialTable});

  /// Table to preselect (e.g. when opened from a table on the Service
  /// board).
  final int? initialTable;

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  late final SettingsController _settings = context.read<SettingsController>();
  // An in-memory cart: a staff order is built and placed in one go.
  late final CartController _cart = CartController(
    MemoryStore(),
    pricingSource: () => _settings.pricing,
  );
  final _instructions = TextEditingController();
  final _search = TextEditingController();
  late int? _table = widget.initialTable;
  String _query = '';
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _cart.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _cart
      ..removeListener(_changed)
      ..dispose();
    _instructions.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _place() async {
    final table = _table;
    if (table == null) {
      await runAdminAction(
        context,
        () async => throw const ValidationException('Choose a table first.'),
      );
      return;
    }
    _cart.updateInstructions(_instructions.text);
    RestaurantOrder? placed;
    final ok = await runAdminAction(context, () async {
      placed = await context.read<OrderController>().placeOrder(
        cart: _cart,
        tableNumber: table,
        source: OrderSource.staff,
      );
    });
    final order = placed;
    if (!ok || order == null || !mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => AdminGuard(
          permission: Permission.viewOrders,
          child: AdminOrderDetailScreen(orderId: order.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final tables = context.watch<SettingsController>().tables.where(
      (t) => t.isActive,
    );
    final placing = context.select<OrderController, bool>((o) => o.isPlacing);
    final q = _query.trim().toLowerCase();
    final dishes = catalog.allItems
        .where(
          (item) =>
              item.isOrderable &&
              (_categoryId == null || item.category.id == _categoryId) &&
              (q.isEmpty || item.name.toLowerCase().contains(q)),
        )
        .toList();
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('New order'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          SectionCard(
            title: 'Table',
            child: DropdownButtonFormField<int>(
              initialValue: _table,
              hint: const Text('Choose a table'),
              items: [
                for (final t in tables)
                  DropdownMenuItem(
                    value: t.number,
                    child: Text(
                      'Table ${AppFormat.table(t.number)} · ${t.seats} seats'
                      '${t.area.isEmpty ? '' : ' · ${t.area}'}',
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _table = value),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AdminSearchField(
            controller: _search,
            hint: 'Search dishes',
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterChipBar<String?>(
            values: [null, for (final c in catalog.categories) c.id],
            selected: _categoryId,
            labelOf: (id) =>
                id == null ? 'All' : (catalog.categoryById(id)?.label ?? id),
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                for (final item in dishes) _DishRow(item: item, cart: _cart),
                if (dishes.isEmpty)
                  const AdminEmpty(
                    icon: Icons.search_off_rounded,
                    title: 'No dishes match',
                    message: 'Sold-out and archived dishes are not listed.',
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Special instructions',
            child: TextField(
              controller: _instructions,
              maxLength: CartController.maxInstructionsLength,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Optional'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_cart.isNotEmpty)
            SectionCard(
              title: 'Summary',
              child: BillSummary(bill: _cart.bill),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: PrimaryButton(
            label: _cart.isEmpty
                ? 'Add dishes to place an order'
                : 'Place order · ${CurrencyFormatter.format(_cart.bill.total)}',
            isLoading: placing,
            onPressed: _cart.isEmpty || placing ? null : _place,
          ),
        ),
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.cart});

  final MenuItem item;
  final CartController cart;

  @override
  Widget build(BuildContext context) {
    final quantity = cart.quantityOfItem(item.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          FoodImage(
            item.image,
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(AppRadii.sm + 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    VegIndicator(isVeg: item.isVeg, size: 11),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(item.name, style: AppTypography.cardTitle),
                    ),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(item.price),
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
          if (quantity == 0)
            IconButton.filled(
              tooltip: 'Add ${item.name}',
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => cart.add(item),
              icon: const Icon(Icons.add_rounded),
            )
          else
            QuantitySelector(
              quantity: quantity,
              compact: true,
              itemName: item.name,
              max: CartController.maxQuantity,
              onIncrement: () => cart.add(item),
              onDecrement: () => cart.quickRemove(item),
            ),
        ],
      ),
    );
  }
}

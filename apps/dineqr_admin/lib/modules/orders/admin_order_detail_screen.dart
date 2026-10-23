import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/admin_session_controller.dart';
import '../../widgets/admin_widgets.dart';
import '../billing/admin_bill_detail_screen.dart';
import 'order_actions.dart';

/// One order for staff: items, instructions, status history, bill and the
/// actions the staff member's role allows.
class AdminOrderDetailScreen extends StatelessWidget {
  const AdminOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminSessionController>();
    final order = context.select<OrderController, RestaurantOrder?>(
      (orders) => orders.byId(orderId),
    );
    final busy = context.select<OrderController, bool>(
      (orders) => orders.isBusy(orderId),
    );
    final invoice = context.select<BillingController, Invoice?>(
      (billing) => billing.forOrder(orderId),
    );
    if (order == null) {
      return Scaffold(
        appBar: AppBar(leading: const AppBackButton()),
        body: const AdminEmpty(
          icon: Icons.receipt_long_outlined,
          title: 'Order not found',
          message: 'It may have been removed by a demo reset.',
        ),
      );
    }
    final action = OrderAction.next(order.status);
    final canAdvance = action != null && action.allowedFor(admin);
    final canCancel =
        order.status.canCancel && admin.can(Permission.cancelOrders);
    return Scaffold(
      backgroundColor: adminBackground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text('Order ${AppFormat.orderNumber(order.id)}'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.page),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FadeSlideIn(child: _Overview(order: order)),
                  const SizedBox(height: AppSpacing.lg),
                  if (canAdvance || canCancel)
                    FadeSlideIn(
                      index: 1,
                      child: Row(
                        children: [
                          if (canAdvance)
                            Expanded(
                              child: PrimaryButton(
                                label: action.label,
                                icon: action.icon,
                                isLoading: busy,
                                onPressed: busy
                                    ? null
                                    : () => advanceOrder(context, order),
                              ),
                            ),
                          if (canAdvance && canCancel)
                            const SizedBox(width: AppSpacing.md),
                          if (canCancel)
                            Expanded(
                              child: SecondaryButton(
                                label: 'Cancel order',
                                icon: Icons.cancel_outlined,
                                onPressed: busy
                                    ? null
                                    : () => cancelOrder(context, order),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    index: 2,
                    child: SectionCard(
                      title: 'Items (${order.itemCount})',
                      child: Column(
                        children: [
                          for (final line in order.lines)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.md,
                              ),
                              child: Row(
                                children: [
                                  FoodImage(
                                    line.image,
                                    width: 44,
                                    height: 44,
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.sm + 2,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            VegIndicator(
                                              isVeg: line.isVeg,
                                              size: 11,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                '${line.quantity} × ${line.name}',
                                                style: AppTypography.cardTitle,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (line.options.isNotEmpty)
                                          Text(
                                            line.options.join(' · '),
                                            style: AppTypography.caption,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    CurrencyFormatter.format(line.lineTotal),
                                    style: AppTypography.label.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (order.specialInstructions.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.warningSoft,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.md,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.sticky_note_2_outlined,
                                    color: AppColors.warning,
                                    size: 20,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      order.specialInstructions,
                                      style: AppTypography.label.copyWith(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    index: 3,
                    child: SectionCard(
                      title: 'Status history',
                      child: _History(order: order),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FadeSlideIn(
                    index: 4,
                    child: SectionCard(
                      title: 'Bill',
                      trailing: invoice == null
                          ? null
                          : PaymentStatusBadge(status: invoice.status),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          BillSummary(
                            bill: order.bill,
                            paid: invoice?.amountPaid,
                            refunded: invoice?.amountRefunded,
                            outstanding: invoice?.outstanding,
                          ),
                          if (invoice != null &&
                              admin.can(Permission.viewBills)) ...[
                            const SizedBox(height: AppSpacing.md),
                            SecondaryButton(
                              label: 'Open bill ${invoice.billNumber}',
                              icon: Icons.request_quote_outlined,
                              height: 46,
                              onPressed: () => pushAdminPage<void>(
                                context,
                                AdminBillDetailScreen(invoiceId: invoice.id),
                                permission: Permission.viewBills,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (order.feedback != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    SectionCard(
                      title: 'Guest feedback',
                      trailing: StarRow(rating: order.feedback!.rating),
                      child: Text(
                        order.feedback!.comment.isEmpty
                            ? 'No comment.'
                            : '"${order.feedback!.comment}"',
                        style: AppTypography.bodySecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.tableLabel,
                  style: AppTypography.headline.copyWith(fontSize: 22),
                ),
              ),
              OrderStatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoRow('Placed', AppFormat.dateTime(order.createdAt)),
          if (order.isActive)
            InfoRow(
              'Age',
              '${AppFormat.minutes(order.ageInMinutes(now))}'
                  '${order.isOverdue(now) ? ' · past the estimate' : ''}',
              valueColor: order.isOverdue(now) ? AppColors.error : null,
            ),
          InfoRow('Ready estimate', AppFormat.time(order.estimatedReadyAt)),
          InfoRow('Source', switch (order.source) {
            OrderSource.guest => 'Guest (QR ordering)',
            OrderSource.staff => 'Entered by staff',
            OrderSource.demoSeed => 'Sample data',
          }),
          if (order.isCancelled)
            InfoRow(
              'Cancelled',
              order.cancelReason.isEmpty ? '—' : order.cancelReason,
              valueColor: AppColors.error,
            ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.order});

  final RestaurantOrder order;

  @override
  Widget build(BuildContext context) {
    final entries = order.statusTimes.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return Column(
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  entry.key == OrderStatus.cancelled
                      ? Icons.cancel_rounded
                      : Icons.check_circle_rounded,
                  size: 18,
                  color: entry.key == OrderStatus.cancelled
                      ? AppColors.error
                      : AppColors.success,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(entry.key.label, style: AppTypography.label),
                ),
                Text(AppFormat.time(entry.value), style: AppTypography.caption),
              ],
            ),
          ),
      ],
    );
  }
}

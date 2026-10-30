import '../utils/currency.dart';
import 'cart_item.dart';
import 'discount_offer.dart';
import 'pricing.dart';
import 'promotion.dart';

/// The saving on one cart line: a special offer on its dish, or a combo's
/// saving over its dishes bought separately. [amount] covers the whole line.
class LineSaving {
  const LineSaving({
    required this.kind,
    required this.amount,
    required this.promotionId,
    required this.label,
  });

  final DiscountKind kind;
  final Money amount;
  final String promotionId;
  final String label;
}

/// A cart priced with its offers: each line's saving, what the discount is
/// made of, and the bill.
class CartQuote {
  const CartQuote({
    required this.savings,
    required this.discounts,
    required this.bill,
    required this.itemSavings,
    required this.couponDiscount,
    this.coupon,
  });

  static const empty = CartQuote(
    savings: {},
    discounts: [],
    bill: BillBreakdown.empty,
    itemSavings: Money.zero,
    couponDiscount: Money.zero,
  );

  /// Savings by cart line id ([CartItem.id]); lines without one are absent.
  final Map<String, LineSaving> savings;
  final List<DiscountLine> discounts;
  final BillBreakdown bill;

  /// What special offers and combos save together.
  final Money itemSavings;
  final Money couponDiscount;

  /// The coupon, when it took effect (it may be below its minimum).
  final DiscountOffer? coupon;

  /// What the coupon's minimum spend is checked against.
  Money get subtotalAfterSavings => bill.subtotal - itemSavings;

  LineSaving? savingFor(String lineId) => savings[lineId];
}

/// How a cart is priced with its offers. The same steps as the server's
/// Pricing.Apply, which has the final word (the app only previews):
///
/// 1. each dish line gets the best live special offer covering its dish
///    (one per line, never more than the dish; the first of equally good
///    offers wins) and each combo line its combo's saving;
/// 2. the coupon applies to what is left, and its minimum spend is checked
///    against that;
/// 3. service charge and tax follow ([BillBreakdown.fromSubtotal]).
abstract final class OfferPricing {
  /// The order's discount label when it has several savings.
  static const combinedLabel = 'Offers & savings';

  /// Display (and tie-break) order: sort order, then id.
  static int byOrder(Promotion a, Promotion b) {
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  }

  /// The special offers live on [today], in tie-break order.
  static List<Promotion> liveSpecials(
    Iterable<Promotion> promotions,
    DateTime today,
  ) =>
      promotions.where((p) => p.isSpecial && p.isLiveOn(today)).toList()
        ..sort(byOrder);

  /// The best of [specials] (live, in tie-break order) for one [itemId]
  /// unit costing [unitPrice], or null when none takes anything off.
  static ({Promotion offer, Money perUnit})? bestSpecial(
    String itemId,
    Money unitPrice,
    List<Promotion> specials,
  ) {
    ({Promotion offer, Money perUnit})? best;
    for (final special in specials) {
      if (!special.isSpecial || !special.covers(itemId)) continue;
      final perUnit = special.unitDiscount(unitPrice);
      if (perUnit.compareTo(best?.perUnit ?? Money.zero) > 0) {
        best = (offer: special, perUnit: perUnit);
      }
    }
    return best;
  }

  /// [specials] must be live and in tie-break order ([liveSpecials]);
  /// [coupon] must be usable today.
  static CartQuote quote({
    required List<CartItem> lines,
    required List<Promotion> specials,
    required PricingConfig config,
    DiscountOffer? coupon,
  }) {
    final savings = <String, LineSaving>{};
    for (final line in lines) {
      final combo = line.combo;
      if (combo != null) {
        final saving = combo.saving * line.quantity;
        if (saving.paise > 0) {
          savings[line.id] = LineSaving(
            kind: DiscountKind.combo,
            amount: saving,
            promotionId: combo.combo.id,
            label: combo.combo.title,
          );
        }
        continue;
      }
      final best = bestSpecial(line.item.id, line.unitPrice, specials);
      if (best != null) {
        savings[line.id] = LineSaving(
          kind: DiscountKind.special,
          amount: best.perUnit * line.quantity,
          promotionId: best.offer.id,
          label: best.offer.title,
        );
      }
    }

    // One entry per promotion, in the order its lines appear.
    final discounts = <DiscountLine>[];
    for (final line in lines) {
      final saving = savings[line.id];
      if (saving == null) continue;
      final index = discounts.indexWhere((d) => d.ref == saving.promotionId);
      if (index >= 0) {
        discounts[index] = discounts[index].plus(saving.amount);
      } else {
        discounts.add(
          DiscountLine(
            kind: saving.kind,
            label: saving.label,
            amount: saving.amount,
            ref: saving.promotionId,
          ),
        );
      }
    }

    final subtotal = Money.sum(lines.map((line) => line.lineTotal));
    final itemSavings = Money.sum(savings.values.map((s) => s.amount));
    final couponDiscount =
        coupon?.discountFor(subtotal - itemSavings) ?? Money.zero;
    if (!couponDiscount.isZero) {
      discounts.add(
        DiscountLine(
          kind: DiscountKind.coupon,
          label: 'Offer ${coupon!.code}',
          amount: couponDiscount,
          ref: coupon.code,
        ),
      );
    }
    final label = switch (discounts.length) {
      0 => null,
      1 => discounts.single.label,
      _ => combinedLabel,
    };
    return CartQuote(
      savings: Map.unmodifiable(savings),
      discounts: List.unmodifiable(discounts),
      bill: BillBreakdown.fromSubtotal(
        subtotal,
        config,
        discount: itemSavings + couponDiscount,
        discountLabel: label,
        discounts: discounts,
      ),
      itemSavings: itemSavings,
      couponDiscount: couponDiscount,
      coupon: couponDiscount.isZero ? null : coupon,
    );
  }
}

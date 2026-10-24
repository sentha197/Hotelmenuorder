import 'dart:async';

import 'package:dineqr_core/dineqr_core.dart';
import 'package:dineqr_design_system/dineqr_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/routes.dart';
import '../../state/session_controller.dart';
import '../../state/shell_controller.dart';
import '../menu/menu_widgets.dart';

/// Screen 4: home with search, categories, promotions and popular dishes.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Results update once typing pauses, not on every keystroke.
  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _search.clear();
    setState(() => _query = '');
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final searching = _query.trim().isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: GestureDetector(
          onTap: () => _searchFocus.unfocus(),
          behavior: HitTestBehavior.translucent,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: _HomeHeader(
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: _onQueryChanged,
                  onClear: _clearSearch,
                ),
              ),
              ...switch (catalog.state) {
                LoadState.loading => [
                  const SliverToBoxAdapter(child: _HomeSkeleton()),
                ],
                LoadState.error => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Menu unavailable',
                      message: 'We could not load the menu. Please try again.',
                      actionLabel: 'Retry',
                      onAction: () => catalog.load(force: true),
                    ),
                  ),
                ],
                LoadState.ready when searching => _searchResults(catalog),
                LoadState.ready => _sections(catalog),
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchResults(CatalogController catalog) {
    final results = catalog.filter(MenuFilter(query: _query));
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.xl,
            AppSpacing.page,
            AppSpacing.xs,
          ),
          child: Text(
            results.isEmpty
                ? 'No results'
                : '${results.length} ${results.length == 1 ? 'dish' : 'dishes'} '
                      'for "${_query.trim()}"',
            style: AppTypography.label.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ),
      if (results.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No dishes found',
            message: 'Try another dish name, like "biryani" or "paneer".',
            actionLabel: 'Clear search',
            onAction: _clearSearch,
          ),
        )
      else
        SliverList.builder(
          itemCount: results.length,
          itemBuilder: (context, index) => FadeSlideIn(
            key: ValueKey('search-${results[index].id}'),
            index: index,
            child: FoodListTile(
              item: results[index],
              heroTag: 'home-search-${results[index].id}',
            ),
          ),
        ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
    ];
  }

  List<Widget> _sections(CatalogController catalog) {
    if (catalog.items.isEmpty) {
      return [
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.restaurant_menu_rounded,
            title: 'Menu coming soon',
            message: 'The restaurant has not published any dishes yet.',
          ),
        ),
      ];
    }
    final popular = catalog.popular;
    final recommended = catalog.recommended;
    final specials = catalog.chefSpecials;
    final promos = _promosFor(catalog);
    final offers = context
        .watch<SettingsController>()
        .settings
        .offers
        .where((offer) => offer.isActive)
        .toList(growable: false);
    final mains = _activeCategory(catalog, MenuCategory.mainCourse.id);
    return [
      SliverToBoxAdapter(child: _CategoryRow(catalog: catalog)),
      if (promos.isNotEmpty)
        SliverToBoxAdapter(child: _PromoCarousel(promos: promos)),
      if (popular.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Popular Dishes',
            actionLabel: 'View All',
            onAction: () =>
                context.read<ShellController>().select(ShellTab.menu),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 252,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                4,
                AppSpacing.page,
                14,
              ),
              itemCount: popular.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => FadeSlideIn(
                index: index,
                offset: const Offset(0.25, 0),
                child: FoodCard(
                  item: popular[index],
                  heroTag: 'home-popular-${popular[index].id}',
                ),
              ),
            ),
          ),
        ),
      ],
      if (offers.isNotEmpty)
        SliverToBoxAdapter(child: _OffersStrip(offers: offers)),
      if (recommended.isNotEmpty) ...[
        const SliverToBoxAdapter(
          child: SectionHeader(
            title: 'Recommended',
            padding: EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page - 8,
              AppSpacing.sm,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 134,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                4,
                AppSpacing.page,
                14,
              ),
              itemCount: recommended.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) => FadeSlideIn(
                index: index,
                offset: const Offset(0.25, 0),
                child: _RecommendedCard(
                  item: recommended[index],
                  heroTag: 'home-recommended-${recommended[index].id}',
                ),
              ),
            ),
          ),
        ),
      ],
      if (specials.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            title: "Chef's Specials",
            actionLabel: mains?.label,
            onAction: mains == null
                ? null
                : () => AppNav.openMenu(context, category: mains),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.sm,
              AppSpacing.page - 8,
              0,
            ),
          ),
        ),
        SliverList.builder(
          itemCount: specials.length,
          itemBuilder: (context, index) => FadeSlideIn(
            index: index,
            child: FoodListTile(
              item: specials[index],
              heroTag: 'home-special-${specials[index].id}',
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
    ];
  }
}

/// The category with [id] if guests can currently browse it.
MenuCategory? _activeCategory(CatalogController catalog, String id) =>
    catalog.categories.where((c) => c.id == id).firstOrNull;

/// Banners built from the live menu: a promotion is left out when its dish
/// or category is not available, and prices come from the menu.
List<_Promo> _promosFor(CatalogController catalog) {
  final chicken = catalog.items
      .where((item) => item.id == 'chicken_65' && item.isOrderable)
      .firstOrNull;
  final mains = _activeCategory(catalog, MenuCategory.mainCourse.id);
  final desserts = _activeCategory(catalog, MenuCategory.desserts.id);
  final dessertPrices = [
    for (final item in catalog.items)
      if (item.category == desserts && item.isOrderable) item.price,
  ]..sort((a, b) => a.compareTo(b));
  return [
    if (chicken != null)
      _Promo(
        eyebrow: "CHEF'S PICK",
        title: 'Crispy, fiery',
        highlight: chicken.name,
        cta: 'Order now',
        image: chicken.image,
        onTap: (context) => AppNav.openDish(context, chicken),
      ),
    if (mains != null && catalog.countIn(mains) > 0)
      _Promo(
        eyebrow: 'SLOW-COOKED DUM',
        title: 'Biryani',
        highlight: 'Festival',
        cta: 'Explore ${mains.label.toLowerCase()}',
        image: 'assets/images/chicken_biryani.jpg',
        onTap: (context) => AppNav.openMenu(context, category: mains),
      ),
    if (desserts != null && dessertPrices.isNotEmpty)
      _Promo(
        eyebrow:
            '${desserts.label.toUpperCase()} FROM '
            '${CurrencyFormatter.format(dessertPrices.first)}',
        title: 'Sweet',
        highlight: 'Endings',
        cta: 'See ${desserts.label.toLowerCase()}',
        image: 'assets/images/gulab_jamun.jpg',
        onTap: (context) => AppNav.openMenu(context, category: desserts),
      ),
  ];
}

/// Landscape dish card for the Recommended carousel.
class _RecommendedCard extends StatelessWidget {
  const _RecommendedCard({required this.item, required this.heroTag});

  final MenuItem item;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => AppNav.openDish(context, item, heroTag: heroTag),
      scale: 0.97,
      child: Container(
        width: 286,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadii.lg + 4),
          border: Border.all(color: AppColors.divider),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            SoldOutVeil(
              soldOut: !item.isOrderable,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Hero(
                tag: heroTag,
                child: FoodImage(
                  item.image,
                  width: 96,
                  height: 96,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      VegIndicator(isVeg: item.isVeg, size: 12),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.name,
                          style: AppTypography.cardTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RatingBadge(
                    rating: item.rating,
                    reviewCount: item.reviewCount,
                    size: 13,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          CurrencyFormatter.format(item.price),
                          style: AppTypography.price.copyWith(fontSize: 15),
                        ),
                      ),
                      AddToCartControl(item: item),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coupons the restaurant has switched on. "Apply" adds the code to the
/// cart; it reduces the bill once the cart meets the offer's minimum.
class _OffersStrip extends StatelessWidget {
  const _OffersStrip({required this.offers});

  final List<DiscountOffer> offers;

  void _apply(BuildContext context, DiscountOffer offer) {
    final cart = context.read<CartController>();
    final problem = cart.applyOffer(offer.code);
    HapticFeedback.selectionClick();
    showAppSnackBar(
      context,
      switch (problem) {
        null => '${offer.code} applied to your cart',
        OfferError.belowMinimum =>
          '${offer.code} saved. Add '
              '${CurrencyFormatter.format(offer.shortfall(cart.subtotal))} '
              'more to use it.',
        final other => other.message,
      },
      icon: problem == null
          ? Icons.check_circle_rounded
          : Icons.info_outline_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final applied = context.select<CartController, String?>(
      (cart) => cart.offerCode,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Offers for You'),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              2,
              AppSpacing.page,
              8,
            ),
            itemCount: offers.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final offer = offers[index];
              return FadeSlideIn(
                index: index,
                offset: const Offset(0.25, 0),
                child: _OfferTicket(
                  offer: offer,
                  applied: offer.code == applied,
                  onApply: () => _apply(context, offer),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OfferTicket extends StatelessWidget {
  const _OfferTicket({
    required this.offer,
    required this.applied,
    required this.onApply,
  });

  final DiscountOffer offer;
  final bool applied;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.lg);
    return Semantics(
      button: !applied,
      label:
          '${offer.title.isEmpty ? offer.code : offer.title}. ${offer.summary}. '
          'Code ${offer.code}${applied ? ', applied' : ''}',
      excludeSemantics: true,
      child: Pressable(
        onTap: applied ? null : onApply,
        scale: 0.97,
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.medium),
          width: 272,
          decoration: BoxDecoration(
            color: applied ? AppColors.successSoft : AppColors.card,
            borderRadius: radius,
            border: Border.all(
              color: applied ? AppColors.success : AppColors.border,
            ),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 50,
                decoration: BoxDecoration(
                  gradient: applied ? null : AppColors.emberGradient,
                  color: applied ? AppColors.success : null,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppRadii.lg),
                  ),
                ),
                child: Icon(
                  applied ? Icons.check_rounded : Icons.local_offer_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          offer.benefit,
                          if (offer.maxDiscount case final cap?)
                            'up to ${CurrencyFormatter.format(cap)}',
                        ].join(' '),
                        style: AppTypography.cardTitle.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (!offer.minSubtotal.isZero)
                            'Above ${CurrencyFormatter.format(offer.minSubtotal)}',
                          if (offer.title.isNotEmpty) offer.title,
                        ].join(' · '),
                        style: AppTypography.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        applied ? 'APPLIED · ${offer.code}' : offer.code,
                        style: AppTypography.overline.copyWith(
                          color: applied
                              ? AppColors.success
                              : AppColors.primary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!applied)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      'APPLY',
                      style: AppTypography.label.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Good morning/afternoon/evening", in restaurant time. It re-reads the
/// clock exactly when the band changes and whenever the app returns to the
/// foreground, so a session left open overnight never shows a stale greeting.
class _GreetingLine extends StatefulWidget {
  const _GreetingLine({required this.utcOffsetMinutes});

  /// Only used to recompute when the restaurant's time zone changes;
  /// [RestaurantTime] itself holds the offset.
  final int utcOffsetMinutes;

  @override
  State<_GreetingLine> createState() => _GreetingLineState();
}

class _GreetingLineState extends State<_GreetingLine>
    with WidgetsBindingObserver {
  Timer? _timer;
  DayGreeting _greeting = RestaurantTime.greeting(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  @override
  void didUpdateWidget(_GreetingLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.utcOffsetMinutes != widget.utcOffsetMinutes) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    final current = RestaurantTime.greeting(DateTime.now());
    if (current != _greeting) setState(() => _greeting = current);
    _schedule();
  }

  /// Wakes up just after the next band boundary. A clock change can put that
  /// in the past, so never schedule a non-positive delay.
  void _schedule() {
    _timer?.cancel();
    final now = DateTime.now();
    final due =
        RestaurantTime.nextGreetingChange(now).difference(now) +
        const Duration(seconds: 1);
    _timer = Timer(
      due > Duration.zero ? due : const Duration(minutes: 1),
      _refresh,
    );
  }

  @override
  Widget build(BuildContext context) => Text(
    '${_greeting.label}!',
    style: AppTypography.caption.copyWith(
      color: Colors.white.withValues(alpha: 0.8),
      fontSize: 13,
    ),
  );
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final restaurant = context.select<SettingsController, String>(
      (settings) => settings.settings.name,
    );
    // Rebuilds the greeting when an admin changes the restaurant's time zone.
    final utcOffsetMinutes = context.select<SettingsController, int>(
      (settings) => settings.settings.utcOffsetMinutes,
    );
    return BrandPanel(
      watermark: true,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.md,
            AppSpacing.page,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: DineQrLockup(height: 36, onDark: true),
                      ),
                    ),
                  ),
                  if (session.tableNumber != null)
                    Pressable(
                      onTap: () =>
                          context.read<ShellController>().select(ShellTab.more),
                      semanticLabel:
                          'Ordering at ${session.tableLabel}. Open table options.',
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadii.pill,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              session.isTakeaway
                                  ? Icons.shopping_bag_rounded
                                  : Icons.table_restaurant_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              session.tableLabel,
                              style: AppTypography.label.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      restaurant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              _GreetingLine(utcOffsetMinutes: utcOffsetMinutes),
              Text(
                'What are you craving today?',
                style: AppTypography.screenTitle.copyWith(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _SearchField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onClear: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => focusNode.unfocus(),
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: 'Search for dishes...',
            fillColor: Colors.white,
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.primary,
            ),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: onClear,
                  ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              borderSide: const BorderSide(
                color: AppColors.warmOrange,
                width: 1.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.catalog});

  final CatalogController catalog;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page - 4,
          AppSpacing.lg,
          AppSpacing.page - 4,
          0,
        ),
        children: [
          FadeSlideIn(
            offset: const Offset(0, 0.25),
            child: _CategoryBubble(
              label: 'All',
              count: catalog.countIn(null),
              icon: Icons.restaurant_menu_rounded,
              onTap: () => AppNav.openMenu(context),
            ),
          ),
          for (final (index, category)
              in catalog.categories
                  .where((c) => catalog.countIn(c) > 0)
                  .indexed)
            FadeSlideIn(
              index: index + 1,
              offset: const Offset(0, 0.25),
              child: _CategoryBubble(
                label: category.label,
                count: catalog.countIn(category),
                image: category.coverImage,
                onTap: () => AppNav.openMenu(context, category: category),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryBubble extends StatelessWidget {
  const _CategoryBubble({
    required this.label,
    required this.count,
    required this.onTap,
    this.image,
    this.icon,
  });

  final String label;
  final int count;
  final VoidCallback onTap;
  final String? image;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: '$label, $count dishes',
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const SweepGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.vibrantOrange,
                    AppColors.warmOrange,
                    AppColors.accentRed,
                    AppColors.primary,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: icon != null
                    ? Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppColors.brandGradient,
                        ),
                        child: Icon(icon, color: Colors.white, size: 26),
                      )
                    : ClipOval(child: FoodImage(image!, width: 55, height: 55)),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Promo {
  const _Promo({
    required this.eyebrow,
    required this.title,
    required this.highlight,
    required this.cta,
    required this.image,
    required this.onTap,
  });

  final String eyebrow;
  final String title;

  /// Second line of the title, shown in the layered brand style.
  final String highlight;
  final String cta;
  final String image;
  final void Function(BuildContext context) onTap;
}

class _PromoCarousel extends StatefulWidget {
  const _PromoCarousel({required this.promos});

  final List<_Promo> promos;

  @override
  State<_PromoCarousel> createState() => _PromoCarouselState();
}

class _PromoCarouselState extends State<_PromoCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _advance());
  }

  void _advance() {
    // Only auto-advance while visible and when motion is welcome.
    if (!mounted ||
        !_controller.hasClients ||
        Motion.reduced(context) ||
        !TickerMode.getValuesNotifier(context).value.enabled) {
      return;
    }
    _controller.animateToPage(
      (_page + 1) % widget.promos.length,
      duration: const Duration(milliseconds: 650),
      curve: Motion.emphasized,
    );
  }

  @override
  void didUpdateWidget(covariant _PromoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A banner can disappear when its dish or category becomes unavailable.
    if (_page >= widget.promos.length) _page = widget.promos.length - 1;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          height: 164,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.promos.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  // How far this banner is from the centre (-1..1), for a
                  // parallax shift of the plate.
                  var delta = 0.0;
                  if (_controller.hasClients &&
                      _controller.position.haveDimensions) {
                    delta = ((_controller.page ?? 0) - index).clamp(-1.0, 1.0);
                  }
                  return _PromoBanner(
                    promo: widget.promos[index],
                    parallax: delta,
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.promos.length; i++)
              AnimatedContainer(
                duration: Motion.of(context, Motion.medium),
                curve: Motion.standard,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page ? null : AppColors.inactive,
                  gradient: i == _page ? AppColors.emberGradient : null,
                  borderRadius: AppRadii.pill,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.promo, required this.parallax});

  final _Promo promo;
  final double parallax;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => promo.onTap(context),
      scale: 0.98,
      semanticLabel: '${promo.title} ${promo.highlight}. ${promo.cta}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: [
            const BoxShadow(color: AppColors.panelLip, offset: Offset(0, 3)),
            BoxShadow(
              color: AppColors.deepRed.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: BrandPanel(
          gradient: AppColors.bannerGradient,
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final plate = constraints.maxHeight * 1.08;
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: Stack(
                  children: [
                    Positioned(
                      right: -plate * 0.18 + parallax * 46,
                      top: (constraints.maxHeight - plate) / 2,
                      child: Transform.rotate(
                        angle: parallax * 0.25,
                        child: Container(
                          width: plate,
                          height: plate,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 4,
                            ),
                            boxShadow: AppShadows.floating,
                          ),
                          child: ClipOval(
                            child: FoodImage(
                              promo.image,
                              width: plate,
                              height: plate,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.xl,
                      top: 0,
                      bottom: 0,
                      width: constraints.maxWidth * 0.56,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            promo.eyebrow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.overline.copyWith(
                              color: AppColors.peach,
                              fontSize: 10,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  promo.title,
                                  style: AppTypography.screenTitle.copyWith(
                                    color: Colors.white,
                                    fontSize: 19,
                                    height: 1.15,
                                  ),
                                ),
                                LayeredGradientText(
                                  promo.highlight,
                                  style: AppTypography.headline.copyWith(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    height: 1.15,
                                  ),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [Colors.white, AppColors.peach],
                                  ),
                                  baseColor: AppColors.depthOnRed,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: AppRadii.pill,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    promo.cta,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.caption.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 14,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return BrandShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          AppSpacing.lg,
          AppSpacing.page,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 4; i++)
                  const Column(
                    children: [
                      SkeletonBox(width: 64, height: 64, circle: true),
                      SizedBox(height: 8),
                      SkeletonBox(width: 48, height: 10),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const SkeletonBox(height: 164, radius: AppRadii.xl),
            const SizedBox(height: AppSpacing.xl),
            const SkeletonBox(width: 140, height: 16),
            const SizedBox(height: AppSpacing.md),
            const Row(
              children: [
                Expanded(child: _CardSkeleton()),
                SizedBox(width: AppSpacing.md),
                Expanded(child: _CardSkeleton()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Food-card shaped placeholder: image block, title and price lines.
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonBox(height: 120, radius: AppRadii.lg),
        SizedBox(height: 10),
        SkeletonBox(width: 110, height: 12),
        SizedBox(height: 8),
        Row(
          children: [
            SkeletonBox(width: 56, height: 14),
            Spacer(),
            SkeletonBox(width: 32, height: 32, circle: true),
          ],
        ),
      ],
    );
  }
}

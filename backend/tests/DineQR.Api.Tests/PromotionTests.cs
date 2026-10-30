using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;

namespace DineQR.Api.Tests;

/// Special offers, combos and coupons: what the admin can set up, and what
/// the server charges for an order (the apps' totals are only a preview).
/// Every offer a test creates is deleted after it, so other tests' totals
/// never change.
[Collection(ApiCollection.Name)]
public class PromotionTests(ApiFactory api) : IAsyncLifetime
{
    // Seeded dishes: samosa ₹60 (veg, no options), french fries ₹120 (add-on
    // cheese dip ₹35), spring roll ₹140.
    private const string Samosa = "samosa";
    private const string Fries = "french_fries";
    private const string SpringRoll = "spring_roll";

    private readonly List<string> _promotions = [];
    private readonly List<string> _coupons = [];
    private HttpClient? _owner;

    public Task InitializeAsync() => Task.CompletedTask;

    public async Task DisposeAsync()
    {
        var owner = await OwnerAsync();
        foreach (var id in _promotions) await owner.DeleteAsync($"/api/v1/admin/promotions/{id}");
        foreach (var code in _coupons) await owner.DeleteAsync($"/api/v1/admin/offers/{code}");
    }

    private async Task<HttpClient> OwnerAsync() => _owner ??= await api.OwnerAsync();

    // ---------------------------------------------------------------- helpers

    private static string NewId() => $"t_{Guid.NewGuid():N}"[..24];

    private static PromotionDto Special(string title, int percentBasisPoints, params string[] dishes) => new(
        NewId(), "special", title, "On selected dishes", "", null, null, true,
        [.. dishes.Select(d => new PromotionItemDto(d))], "percent", percentBasisPoints);

    private static PromotionDto FlatSpecial(string title, int paise, params string[] dishes) =>
        Special(title, 0, dishes) with { DiscountType = "flat", Value = paise };

    private static PromotionDto Combo(string title, long price, params (string Dish, int Quantity)[] parts) => new(
        NewId(), "combo", title, "Dishes that go together", "", null, null, true,
        [.. parts.Select(p => new PromotionItemDto(p.Dish, p.Quantity))], ComboPrice: price);

    private Task<HttpResponseMessage> PutPromotionAsync(HttpClient client, PromotionDto dto) =>
        client.PutAsJsonAsync($"/api/v1/admin/promotions/{dto.Id}", dto, Json.Options);

    /// Saves [dto] as the owner and deletes it after the test.
    private async Task<PromotionDto> CreateAsync(PromotionDto dto)
    {
        var saved = await (await PutPromotionAsync(await OwnerAsync(), dto)).ReadAsync<PromotionDto>();
        _promotions.Add(saved.Id);
        return saved;
    }

    private static OfferDto Coupon(string code, int percentBasisPoints, long? min = null) =>
        new(code, "Test coupon", "percent", percentBasisPoints, min, null, true);

    private async Task<OfferDto> CreateAsync(OfferDto dto)
    {
        var saved = await (await (await OwnerAsync()).PutAsJsonAsync($"/api/v1/admin/offers/{dto.Code}", dto,
            Json.Options)).ReadAsync<OfferDto>();
        _coupons.Add(saved.Code);
        return saved;
    }

    private static string NewCode() => $"T{Guid.NewGuid():N}"[..12].ToUpperInvariant();

    private static object Dish(string itemId, int quantity, object? options = null) =>
        new { itemId, quantity, options };

    private static object ComboLine(string comboId, int quantity) => new { comboId, quantity };

    private static Task<HttpResponseMessage> OrderAsync(HttpClient guest, object[] lines, string? offerCode = null,
        long? expectedTotal = null) =>
        guest.PostJsonAsync("/api/v1/orders", new
        {
            lines,
            idempotencyKey = HttpTestExtensions.Key(),
            offerCode,
            expectedTotal,
        });

    private static async Task<OrderDto> PlaceAsync(HttpClient guest, object[] lines, string? offerCode = null) =>
        await (await OrderAsync(guest, lines, offerCode)).ReadAsync<OrderDto>();

    /// The restaurant's pricing as it is now (other tests may change it).
    private async Task<(RestaurantSettings Pricing, DateOnly Today)> RestaurantAsync()
    {
        var settings = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        var pricing = new RestaurantSettings
        {
            TaxRateBasisPoints = settings.TaxRate,
            ServiceChargeBasisPoints = settings.ServiceRate,
            TaxName = settings.TaxName,
            UtcOffsetMinutes = settings.UtcOffset,
        };
        return (pricing, OfferRules.Today(pricing, DateTime.UtcNow));
    }

    private async Task<long> TotalAsync(long subtotal, long discount) =>
        Pricing.Compute(subtotal, (await RestaurantAsync()).Pricing, discount).Total;

    private async Task<PromotionDto> StaffViewAsync(string id)
    {
        var menu = await (await (await OwnerAsync()).GetAsync("/api/v1/admin/menu")).ReadAsync<MenuDto>();
        return menu.Promotions!.Single(p => p.Id == id);
    }

    private async Task<MenuDto> GuestMenuAsync() =>
        await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();

    private async Task CancelAsync(string orderId)
    {
        var response = await (await OwnerAsync()).PostJsonAsync($"/api/v1/admin/orders/{orderId}/status",
            new { target = "cancelled", reason = "Test cancellation" });
        response.EnsureSuccessStatusCode();
    }

    // ----------------------------------------------------------- management

    [Fact]
    public async Task Only_staff_allowed_to_manage_offers_can_change_them()
    {
        var offer = Special("Staff test", 1000, Samosa);

        var guest = await api.GuestAsync();
        Assert.False((await PutPromotionAsync(guest, offer)).IsSuccessStatusCode);
        var cashier = await api.NewStaffAsync("cashier");
        Assert.Equal(HttpStatusCode.Forbidden, (await PutPromotionAsync(cashier, offer)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await cashier.PutAsJsonAsync($"/api/v1/admin/offers/{NewCode()}", Coupon("NOPE1", 1000), Json.Options))
            .StatusCode);

        // Managers run promotions without being allowed to change settings.
        var manager = await api.NewStaffAsync("manager");
        var saved = await (await PutPromotionAsync(manager, offer)).ReadAsync<PromotionDto>();
        _promotions.Add(saved.Id);
        Assert.Equal(0, saved.Used);
        Assert.Equal(HttpStatusCode.Forbidden, (await cashier.DeleteAsync($"/api/v1/admin/promotions/{saved.Id}"))
            .StatusCode);
        Assert.Equal(HttpStatusCode.NoContent, (await manager.DeleteAsync($"/api/v1/admin/promotions/{saved.Id}"))
            .StatusCode);
    }

    [Fact]
    public async Task Offers_are_validated_on_the_server()
    {
        var owner = await OwnerAsync();
        async Task<string> Refused(PromotionDto dto)
        {
            var response = await PutPromotionAsync(owner, dto);
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            return await response.Content.ReadAsStringAsync();
        }

        await Refused(Special("Too much", 10_001, Samosa));
        await Refused(Special("No dishes", 1000));
        await Refused(Special("Unknown dish", 1000, "no_such_dish"));
        await Refused(Special("X", 1000, Samosa));
        await Refused(Special("Bad id", 1000, Samosa) with { Id = "Bad Id!" });
        // A combo line is stored under the combo's id, so it cannot be a dish's.
        await Refused(Special("Dish id", 1000, Samosa) with { Id = Samosa });
        var (_, today) = await RestaurantAsync();
        await Refused(Special("Backwards", 1000, Samosa) with { StartsOn = today, EndsOn = today.AddDays(-1) });
        await Refused(Special("No uses", 1000, Samosa) with { Limit = 0 });

        // A combo needs two dishes and must cost less than they do separately
        // (2 × ₹60 + ₹120 = ₹240).
        await Refused(Combo("Lonely", 5000, (Samosa, 1)));
        await Refused(Combo("Same price", 24_000, (Samosa, 2), (Fries, 1)));
        Assert.Contains("₹240", await Refused(Combo("Dearer", 25_000, (Samosa, 2), (Fries, 1))));
        await Refused(Combo("Too many", 5000, (Samosa, 11)));

        // A special offer cannot turn into a combo.
        var special = await CreateAsync(Special("Kind test", 1000, Samosa));
        await Refused(Combo("Kind test", 5000, (Samosa, 2)) with { Id = special.Id });
    }

    [Fact]
    public async Task Guests_see_only_live_offers_and_never_their_usage()
    {
        var (_, today) = await RestaurantAsync();
        var live = await CreateAsync(Special("Live", 1000, Samosa) with { Limit = 50 });
        var paused = await CreateAsync(Special("Paused", 1000, Samosa) with { Active = false });
        var ended = await CreateAsync(Special("Ended", 1000, Samosa) with { EndsOn = today.AddDays(-1) });
        var upcoming = await CreateAsync(Special("Upcoming", 1000, Samosa) with { StartsOn = today.AddDays(1) });
        var lastDay = await CreateAsync(Special("Last day", 1000, Samosa) with
        {
            StartsOn = today.AddDays(-3), EndsOn = today,
        });

        var menu = await GuestMenuAsync();
        var ids = menu.Promotions!.Select(p => p.Id).ToHashSet();
        Assert.Contains(live.Id, ids);
        Assert.Contains(lastDay.Id, ids);
        Assert.DoesNotContain(paused.Id, ids);
        Assert.DoesNotContain(ended.Id, ids);
        Assert.DoesNotContain(upcoming.Id, ids);
        var seen = menu.Promotions!.Single(p => p.Id == live.Id);
        Assert.Null(seen.Limit);
        Assert.Null(seen.Used);

        // Staff see every offer, with its usage.
        var staff = await StaffViewAsync(live.Id);
        Assert.Equal(50, staff.Limit);
        Assert.Equal(0, staff.Used);
        Assert.False((await StaffViewAsync(paused.Id)).Active);

        // Switching one off takes it off the guests' menu.
        var toggled = await (await (await OwnerAsync()).PatchAsJsonAsync($"/api/v1/admin/promotions/{live.Id}",
            new { active = false }, Json.Options)).ReadAsync<PromotionDto>();
        Assert.False(toggled.Active);
        Assert.DoesNotContain(live.Id, (await GuestMenuAsync()).Promotions!.Select(p => p.Id));
    }

    // -------------------------------------------------------------- pricing

    [Fact]
    public async Task A_special_offer_discounts_its_dishes_and_the_order_keeps_the_details()
    {
        var offer = await CreateAsync(Special("Snack hour", 2000, Samosa, Fries));
        var guest = await api.GuestAsync();

        var order = await PlaceAsync(guest,
        [
            Dish(Samosa, 2),
            Dish(Fries, 1, new { addOns = new[] { "cheese_dip" } }),
            Dish(SpringRoll, 1),
        ]);

        // 20% of ₹60 = ₹12 per samosa; 20% of ₹155 (fries with dip) = ₹31.
        var samosa = order.Lines.Single(l => l.ItemId == Samosa);
        Assert.Equal(6000, samosa.UnitPrice);
        Assert.Equal(2400, samosa.Discount);
        Assert.Equal(offer.Id, samosa.PromotionId);
        Assert.Equal("Snack hour", samosa.DiscountLabel);
        Assert.Equal(3100, order.Lines.Single(l => l.ItemId == Fries).Discount);
        Assert.Null(order.Lines.Single(l => l.ItemId == SpringRoll).Discount);

        Assert.Equal(12_000 + 15_500 + 14_000, order.Subtotal);
        Assert.Equal(5500, order.Discount);
        Assert.Equal("Snack hour", order.DiscountLabel);
        var line = Assert.Single(order.Discounts!);
        Assert.Equal(("special", "Snack hour", 5500L, offer.Id), (line.Kind, line.Label, line.Amount, line.Ref));
        Assert.Equal(await TotalAsync(order.Subtotal, 5500), order.Total);

        // The bill carries the same breakdown, and the offer counts one use.
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        Assert.Equal(order.Total, bill.Amounts.Total);
        Assert.Equal(5500, Assert.Single(bill.Amounts.Discounts!).Amount);
        Assert.Equal(1, (await StaffViewAsync(offer.Id)).Used);

        // Deleting the offer later leaves the order as it was.
        Assert.Equal(HttpStatusCode.NoContent,
            (await (await OwnerAsync()).DeleteAsync($"/api/v1/admin/promotions/{offer.Id}")).StatusCode);
        var kept = await (await guest.GetAsync($"/api/v1/orders/{order.Id}")).ReadAsync<OrderDto>();
        Assert.Equal(5500, kept.Discount);
        Assert.Equal("Snack hour", kept.Lines.Single(l => l.ItemId == Samosa).DiscountLabel);
    }

    [Fact]
    public async Task The_best_special_offer_wins_and_never_takes_more_than_the_dish()
    {
        await CreateAsync(Special("Ten percent", 1000, Samosa));
        var flat = await CreateAsync(FlatSpecial("Flat hundred", 10_000, Samosa));
        var guest = await api.GuestAsync();

        var order = await PlaceAsync(guest, [Dish(Samosa, 3)]);

        // ₹100 off a ₹60 samosa is capped at ₹60, which beats 10% (₹6).
        var line = Assert.Single(order.Lines);
        Assert.Equal(flat.Id, line.PromotionId);
        Assert.Equal(18_000, line.Discount);
        Assert.Equal(18_000, order.Discount);
        Assert.Equal(0, order.Total);
        Assert.Single(order.Discounts!);
    }

    [Fact]
    public async Task A_combo_is_sold_for_its_price_and_lists_its_dishes()
    {
        // 2 samosas and fries cost ₹240 separately; the combo is ₹199.
        var combo = await CreateAsync(Combo("Snack box", 19_900, (Samosa, 2), (Fries, 1)));
        var guest = await api.GuestAsync();

        var published = Assert.Single((await GuestMenuAsync()).Promotions!, p => p.Id == combo.Id);
        Assert.Equal(19_900, published.ComboPrice);
        Assert.Equal([(Samosa, 2), (Fries, 1)], published.Items!.Select(i => (i.ItemId, i.Quantity)));

        var order = await PlaceAsync(guest, [ComboLine(combo.Id, 2), Dish(Samosa, 1)]);

        var line = order.Lines.Single(l => l.ComboId == combo.Id);
        Assert.Equal(combo.Id, line.ItemId);
        Assert.Equal("Snack box", line.Name);
        Assert.Equal(24_000, line.UnitPrice);
        Assert.Equal(2, line.Quantity);
        Assert.Equal(8200, line.Discount);
        Assert.Equal(OfferRules.ComboCategoryId, line.CategoryId);
        Assert.Equal(["2 × Punjabi Samosa", "French Fries"], line.Options);
        Assert.Equal([(Samosa, 2), (Fries, 1)], line.ComboItems!.Select(p => (p.ItemId, p.Quantity)));
        Assert.True(line.IsVeg);

        Assert.Equal(48_000 + 6000, order.Subtotal);
        Assert.Equal(8200, order.Discount);
        Assert.Equal(await TotalAsync(54_000, 8200), order.Total);
        var saving = Assert.Single(order.Discounts!);
        Assert.Equal(("combo", combo.Id), (saving.Kind, saving.Ref));

        // The kitchen sees what is in it.
        var staffView = await (await (await OwnerAsync()).GetAsync($"/api/v1/admin/orders/{order.Id}"))
            .ReadAsync<OrderDto>();
        Assert.Equal(2, staffView.Lines.Single(l => l.ComboId == combo.Id).ComboItems!.Count);
    }

    [Fact]
    public async Task A_combo_cannot_be_ordered_once_it_ends_or_a_dish_runs_out()
    {
        var (_, today) = await RestaurantAsync();
        var ended = await CreateAsync(Combo("Old box", 19_900, (Samosa, 2), (Fries, 1)) with
        {
            EndsOn = today.AddDays(-1),
        });
        var guest = await api.GuestAsync();
        var refused = await OrderAsync(guest, [ComboLine(ended.Id, 1)]);
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("offerUnavailable", await refused.ErrorCodeAsync());

        var unknown = await OrderAsync(guest, [ComboLine("no_such_combo", 1)]);
        Assert.Equal("offerUnavailable", await unknown.ErrorCodeAsync());

        var combo = await CreateAsync(Combo("Spring box", 25_000, (SpringRoll, 2)));
        var owner = await OwnerAsync();
        (await owner.PatchAsJsonAsync($"/api/v1/admin/menu/items/{SpringRoll}", new { available = false },
            Json.Options)).EnsureSuccessStatusCode();
        try
        {
            var soldOut = await OrderAsync(guest, [ComboLine(combo.Id, 1)]);
            Assert.Equal(HttpStatusCode.Conflict, soldOut.StatusCode);
            Assert.Equal("itemsUnavailable", await soldOut.ErrorCodeAsync());
        }
        finally
        {
            (await owner.PatchAsJsonAsync($"/api/v1/admin/menu/items/{SpringRoll}", new { available = true },
                Json.Options)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task A_coupon_applies_after_item_savings_and_its_minimum_counts_them()
    {
        var special = await CreateAsync(Special("Half price samosa", 5000, Samosa));
        var coupon = await CreateAsync(Coupon(NewCode(), 1000, min: 10_000));
        var guest = await api.GuestAsync();

        // 3 samosas: ₹180, ₹90 after the special: below the coupon's ₹100.
        var small = await PlaceAsync(guest, [Dish(Samosa, 3)], coupon.Code);
        Assert.Equal(9000, small.Discount);
        Assert.Equal("special", Assert.Single(small.Discounts!).Kind);

        // 4 samosas: ₹240, ₹120 after the special, so 10% (₹12) off that.
        var large = await PlaceAsync(guest, [Dish(Samosa, 4)], coupon.Code);
        Assert.Equal(12_000 + 1200, large.Discount);
        Assert.Equal(Pricing.CombinedLabel, large.DiscountLabel);
        Assert.Equal(
            [("special", special.Id, 12_000L), ("coupon", coupon.Code, 1200L)],
            large.Discounts!.Select(d => (d.Kind, d.Ref, d.Amount)));
        Assert.Equal($"Offer {coupon.Code}", large.Discounts![1].Label);
        Assert.Equal(await TotalAsync(24_000, 13_200), large.Total);

        // Only the order that saved with the coupon used it.
        var settings = await (await (await OwnerAsync()).GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        Assert.Equal(1, settings.Offers!.Single(o => o.Code == coupon.Code).Used);
    }

    [Fact]
    public async Task Expired_upcoming_and_paused_offers_never_apply()
    {
        var (_, today) = await RestaurantAsync();
        await CreateAsync(Special("Ended", 5000, Samosa) with { EndsOn = today.AddDays(-1) });
        await CreateAsync(Special("Upcoming", 5000, Samosa) with { StartsOn = today.AddDays(1) });
        await CreateAsync(Special("Paused", 5000, Samosa) with { Active = false });
        var guest = await api.GuestAsync();

        var order = await PlaceAsync(guest, [Dish(Samosa, 2)]);
        Assert.Equal(0, order.Discount);
        Assert.Null(order.Discounts);

        var ended = await CreateAsync(Coupon(NewCode(), 1000) with { EndsOn = today.AddDays(-1) });
        var upcoming = await CreateAsync(Coupon(NewCode(), 1000) with { StartsOn = today.AddDays(2) });
        var published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.DoesNotContain(published.Offers!, o => o.Code == ended.Code || o.Code == upcoming.Code);

        var refused = await OrderAsync(guest, [Dish(Samosa, 2)], ended.Code);
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("offerUnavailable", await refused.ErrorCodeAsync());
        Assert.Contains("ended", await refused.Content.ReadAsStringAsync());
        Assert.Contains("starts", await (await OrderAsync(guest, [Dish(Samosa, 2)], upcoming.Code))
            .Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task An_order_priced_before_an_offer_changed_is_refused()
    {
        var guest = await api.GuestAsync();
        var withoutOffer = await TotalAsync(12_000, 0);
        await CreateAsync(Special("Surprise", 5000, Samosa));

        // The guest saw ₹120 (plus tax); the server now charges less, so the
        // guest reviews the cart rather than paying a total they never saw.
        var response = await OrderAsync(guest, [Dish(Samosa, 2)], expectedTotal: withoutOffer);
        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        Assert.Equal("priceChanged", await response.ErrorCodeAsync());
    }

    // --------------------------------------------------------- usage limits

    [Fact]
    public async Task A_usage_limit_holds_when_orders_arrive_together()
    {
        var offer = await CreateAsync(Special("Only once", 5000, Samosa) with { Limit = 1 });
        var guests = await Task.WhenAll(Enumerable.Range(1, 6).Select(t => api.GuestAsync(table: t)));

        var responses = await Task.WhenAll(guests.Select(g => OrderAsync(g, [Dish(Samosa, 2)])));

        var placed = new List<OrderDto>();
        foreach (var response in responses)
        {
            if (response.IsSuccessStatusCode)
            {
                placed.Add(await response.ReadAsync<OrderDto>());
            }
            else
            {
                // Lost the race after pricing with the offer: asked to review.
                Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
                Assert.Equal("offerUnavailable", await response.ErrorCodeAsync());
            }
        }
        var discounted = Assert.Single(placed, o => o.Discount > 0);
        Assert.Equal(6000, discounted.Discount);
        Assert.Equal(1, (await StaffViewAsync(offer.Id)).Used);
        Assert.DoesNotContain(offer.Id, (await GuestMenuAsync()).Promotions!.Select(p => p.Id));

        // Cancelling that order gives the use back.
        await CancelAsync(discounted.Id);
        Assert.Equal(0, (await StaffViewAsync(offer.Id)).Used);
        var again = await PlaceAsync(guests[0], [Dish(Samosa, 1)]);
        Assert.Equal(3000, again.Discount);
    }

    [Fact]
    public async Task A_used_up_coupon_is_refused_and_disappears()
    {
        var coupon = await CreateAsync(Coupon(NewCode(), 1000) with { Limit = 1 });
        var guest = await api.GuestAsync();

        var first = await PlaceAsync(guest, [Dish(Samosa, 2)], coupon.Code);
        Assert.Equal(1200, first.Discount);

        var second = await OrderAsync(guest, [Dish(Samosa, 2)], coupon.Code);
        Assert.Equal(HttpStatusCode.Conflict, second.StatusCode);
        Assert.Equal("offerUnavailable", await second.ErrorCodeAsync());
        var published = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.DoesNotContain(published.Offers!, o => o.Code == coupon.Code);

        // Cancelling the first order gives its use back.
        await CancelAsync(first.Id);
        var third = await PlaceAsync(guest, [Dish(Samosa, 2)], coupon.Code);
        Assert.Equal(1200, third.Discount);
    }

    [Fact]
    public async Task Retrying_an_order_uses_its_offer_once()
    {
        var offer = await CreateAsync(Special("Retry", 1000, Samosa) with { Limit = 5 });
        var guest = await api.GuestAsync();
        var body = new { lines = new[] { Dish(Samosa, 1) }, idempotencyKey = HttpTestExtensions.Key() };

        var first = await (await guest.PostJsonAsync("/api/v1/orders", body)).ReadAsync<OrderDto>();
        var replay = await (await guest.PostJsonAsync("/api/v1/orders", body)).ReadAsync<OrderDto>();

        Assert.Equal(first.Id, replay.Id);
        Assert.Equal(1, (await StaffViewAsync(offer.Id)).Used);
    }

    // ---------------------------------------------------------- payment

    [Fact]
    public async Task Payment_is_for_the_discounted_total_and_no_more()
    {
        var combo = await CreateAsync(Combo("Pay box", 19_900, (Samosa, 2), (Fries, 1)));
        var guest = await api.GuestAsync();
        var order = await PlaceAsync(guest, [ComboLine(combo.Id, 1)]);
        var bill = await (await guest.GetAsync($"/api/v1/orders/{order.Id}/bill")).ReadAsync<InvoiceDto>();
        Assert.Equal(await TotalAsync(24_000, 4100), bill.Amounts.Total);

        Task<HttpResponseMessage> Intent(long amount) => guest.PostJsonAsync("/api/v1/payments/intents",
            new { invoiceId = bill.Id, amount, method = "upi", idempotencyKey = HttpTestExtensions.Key() });

        // The price before the combo saving is more than is owed.
        var undiscounted = await TotalAsync(24_000, 0);
        Assert.Equal(HttpStatusCode.BadRequest, (await Intent(undiscounted)).StatusCode);

        var intent = await (await Intent(bill.Amounts.Total)).ReadAsync<PaymentIntentResponse>();
        var paid = await (await guest.PostJsonAsync($"/api/v1/payments/{intent.Payment.Id}/confirm",
            new { simulatedOutcome = "success" })).ReadAsync<PaymentResultDto>();
        Assert.Equal("paid", paid.Invoice.Status);
        Assert.Equal(bill.Amounts.Total, paid.Invoice.Paid);
    }

    // ---------------------------------------------------------- coupons

    [Fact]
    public async Task Coupons_keep_their_dates_limits_and_uses_through_every_kind_of_save()
    {
        var (_, today) = await RestaurantAsync();
        var owner = await OwnerAsync();
        var coupon = await CreateAsync(Coupon(NewCode(), 1000) with
        {
            StartsOn = today.AddDays(-1), EndsOn = today.AddDays(30), Limit = 10,
        });
        Assert.Equal(today.AddDays(30), coupon.EndsOn);
        Assert.Equal(10, coupon.Limit);
        await PlaceAsync(await api.GuestAsync(), [Dish(Samosa, 2)], coupon.Code);

        // An app from before the Offers section saves settings with the
        // coupon list (no dates or limits): they are kept.
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        var legacy = settings with
        {
            Offers = [.. settings.Offers!.Select(o => o with { StartsOn = null, EndsOn = null, Limit = null, Used = null })],
        };
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", legacy, Json.Options)).EnsureSuccessStatusCode();
        // A current app saves settings without them: nothing changes either.
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Offers = null }, Json.Options))
            .EnsureSuccessStatusCode();

        var kept = (await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>())
            .Offers!.Single(o => o.Code == coupon.Code);
        Assert.Equal((today.AddDays(-1), today.AddDays(30), 10, 1),
            (kept.StartsOn!.Value, kept.EndsOn!.Value, kept.Limit!.Value, kept.Used!.Value));

        // Renaming keeps the count; the old code is gone.
        var renamed = NewCode();
        var saved = await (await owner.PutAsJsonAsync($"/api/v1/admin/offers/{coupon.Code}",
            kept with { Code = renamed }, Json.Options)).ReadAsync<OfferDto>();
        _coupons.Add(renamed);
        Assert.Equal(1, saved.Used);
        var after = (await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>()).Offers!;
        Assert.DoesNotContain(after, o => o.Code == coupon.Code);

        var paused = await (await owner.PatchAsJsonAsync($"/api/v1/admin/offers/{renamed}", new { active = false },
            Json.Options)).ReadAsync<OfferDto>();
        Assert.False(paused.Active);
        var refused = await OrderAsync(await api.GuestAsync(), [Dish(Samosa, 1)], renamed);
        Assert.Equal("offerUnavailable", await refused.ErrorCodeAsync());
    }
}

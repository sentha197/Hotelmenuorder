using DineQR.Api.Domain;
using DineQR.Api.Services;

namespace DineQR.Api.Tests;

/// The server's pricing must match the app's (dineqr_core pricing.dart)
/// paisa for paisa.
public class PricingTests
{
    private static RestaurantSettings Settings(int tax = 500, int service = 0) =>
        new() { TaxRateBasisPoints = tax, ServiceChargeBasisPoints = service, TaxName = "GST" };

    [Theory]
    [InlineData(1000, 500, 50)]
    [InlineData(1010, 500, 51)] // 50.5 rounds half up
    [InlineData(1009, 500, 50)] // 50.45
    [InlineData(333, 250, 8)] // 8.325
    [InlineData(0, 500, 0)]
    public void Rates_round_half_up_to_the_paisa(long paise, int basisPoints, long expected) =>
        Assert.Equal(expected, Pricing.ApplyRate(paise, basisPoints));

    [Fact]
    public void Discount_then_service_charge_then_tax()
    {
        var bill = Pricing.Compute(100_000, Settings(tax: 500, service: 1000), discount: 10_000, discountLabel: "Offer X");
        Assert.Equal(10_000, bill.Discount);
        Assert.Equal(9_000, bill.Service); // 10% of 90,000
        Assert.Equal(4_950, bill.Tax); // 5% of 99,000
        Assert.Equal(103_950, bill.Total);
        Assert.Equal("Offer X", bill.DiscountLabel);
    }

    [Fact]
    public void A_discount_never_exceeds_the_subtotal()
    {
        var bill = Pricing.Compute(5_000, Settings(), discount: 9_000);
        Assert.Equal(5_000, bill.Discount);
        Assert.Equal(0, bill.Total);
    }

    [Fact]
    public void Percentage_offers_respect_the_minimum_and_the_cap()
    {
        var offer = new DiscountOffer
        {
            Code = "WELCOME10", Type = DiscountType.Percent, Value = 1000, MinSubtotalPaise = 30_000,
            MaxDiscountPaise = 10_000, IsActive = true,
        };
        Assert.Equal(0, Pricing.DiscountFor(offer, 29_999));
        Assert.Equal(5_000, Pricing.DiscountFor(offer, 50_000));
        Assert.Equal(10_000, Pricing.DiscountFor(offer, 500_000));
        offer.IsActive = false;
        Assert.Equal(0, Pricing.DiscountFor(offer, 50_000));
    }

    [Fact]
    public void Flat_offers_never_exceed_the_subtotal()
    {
        var offer = new DiscountOffer { Code = "FEAST75", Type = DiscountType.Flat, Value = 7_500, IsActive = true };
        Assert.Equal(7_500, Pricing.DiscountFor(offer, 80_000));
        Assert.Equal(5_000, Pricing.DiscountFor(offer, 5_000));
    }
}

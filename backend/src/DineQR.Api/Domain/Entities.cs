namespace DineQR.Api.Domain;

// Money is held as integer paise in code (exact, and what the apps use) and
// stored as numeric(14,2) rupees in PostgreSQL. Every property named
// "...Paise" gets that mapping in AppDbContext.

/// A staff login. Maps onto the existing `users` table.
public class User
{
    public long Id { get; set; }
    public string FullName { get; set; } = "";
    public string Email { get; set; } = "";
    public string? Phone { get; set; }
    public string PasswordHash { get; set; } = "";
    public StaffRole Role { get; set; }
    public bool IsActive { get; set; } = true;
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public int FailedLoginCount { get; set; }
    public DateTime? LockedUntil { get; set; }
}

/// One rotation of a sign-in session. Only a hash of the token is stored.
public class RefreshToken
{
    public long Id { get; set; }
    public long UserId { get; set; }
    public User User { get; set; } = null!;

    /// Every rotation of one sign-in shares this id, so a reused (stolen)
    /// token revokes the whole session.
    public Guid SessionId { get; set; }
    public string TokenHash { get; set; } = "";
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }

    /// Absolute end of the session, carried across rotations.
    public DateTime SessionExpiresAt { get; set; }
    public DateTime? RevokedAt { get; set; }
}

/// The restaurant's configuration (one row).
public class RestaurantSettings
{
    public const int SingletonId = 1;

    public int Id { get; set; } = SingletonId;
    public string Name { get; set; } = "";
    public string Phone { get; set; } = "";
    public string Email { get; set; } = "";
    public string Address { get; set; } = "";
    public string TaxRegistration { get; set; } = "";
    public string TaxName { get; set; } = "Taxes";
    public int TaxRateBasisPoints { get; set; }
    public int ServiceChargeBasisPoints { get; set; }
    public int UtcOffsetMinutes { get; set; }
    public bool AllowPartialPayments { get; set; } = true;

    /// Names of the online methods offered (`upi`, `card`, ...).
    public List<string> OnlineMethods { get; set; } = [];

    /// Demo until a verified payment gateway is configured and an owner
    /// switches to live.
    public PaymentMode PaymentMode { get; set; } = PaymentMode.Demo;

    /// ISO code of the currency bills are in ([Currencies]). Fixed once the
    /// first bill exists, so earlier bills never change currency.
    public string Currency { get; set; } = Currencies.Default;
    public string ReceiptFooter { get; set; } = "";
    public bool ShowSoldOutDishes { get; set; } = true;
    public bool AutoUnavailableWhenOutOfStock { get; set; } = true;
    public int PrepBufferMinutes { get; set; } = 5;

    /// Whether the restaurant takes takeaway orders. Off by default: scanning
    /// the takeaway QR is refused until an owner turns it on. This is the
    /// stored configuration behind the takeaway QR code.
    public bool TakeawayOrdersEnabled { get; set; }

    // UPI payments straight to the restaurant's own account, with no payment
    // gateway. Only the public payee details are stored: never a PIN, a card
    // or any bank credential. See [UpiRules] for the validation.

    /// Guests are offered UPI only while this is on (and the details below
    /// are complete).
    public bool UpiEnabled { get; set; }

    /// The restaurant's UPI ID (VPA), e.g. `cafe@okhdfcbank`, lower case.
    public string UpiId { get; set; } = "";

    /// Name shown to the guest in their UPI app.
    public string UpiPayeeName { get; set; } = "";

    /// URL of the restaurant's own merchant QR image, uploaded through
    /// [ImageStorage] ("" when none).
    public string UpiQrImage { get; set; } = "";
    public UpiVerificationMode UpiVerificationMode { get; set; } = UpiVerificationMode.Manual;

    public DateTime UpdatedAt { get; set; }
}

public class DiscountOffer
{
    public string Code { get; set; } = "";
    public string Title { get; set; } = "";
    public DiscountType Type { get; set; }

    /// Basis points for percent offers, paise for flat ones.
    public int Value { get; set; }
    public long MinSubtotalPaise { get; set; }
    public long? MaxDiscountPaise { get; set; }
    public bool IsActive { get; set; } = true;
    public int SortOrder { get; set; }
}

public class MenuCategory
{
    public string Id { get; set; } = "";
    public string Label { get; set; } = "";
    public string CoverImage { get; set; } = "";
    public int SortOrder { get; set; }
    public bool IsActive { get; set; } = true;
}

public class MenuItem
{
    public string Id { get; set; } = "";
    public string CategoryId { get; set; } = "";
    public MenuCategory Category { get; set; } = null!;
    public string Name { get; set; } = "";
    public string Description { get; set; } = "";
    public string ShortDescription { get; set; } = "";
    public long PricePaise { get; set; }
    public string Image { get; set; } = "";
    public List<string> Gallery { get; set; } = [];
    public bool IsVeg { get; set; }
    public double Rating { get; set; }
    public int ReviewCount { get; set; }
    public bool IsPopular { get; set; }
    public bool IsChefSpecial { get; set; }

    /// Shown as a banner in the customer home carousel.
    public bool IsFeatured { get; set; }
    public bool HasSpiceLevel { get; set; }
    public SpiceLevel DefaultSpice { get; set; } = SpiceLevel.Medium;
    public int PrepMinutes { get; set; } = 15;
    public bool IsAvailable { get; set; } = true;
    public bool IsArchived { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public List<MenuItemPortion> Portions { get; set; } = [];
    public List<MenuItemAddOn> AddOns { get; set; } = [];

    /// Whether guests can order it right now.
    public bool IsOrderable => IsAvailable && !IsArchived && Category.IsActive;
}

/// An uploaded dish photo. It lives in the database, not on disk: the API's
/// disk is wiped on every redeploy, which used to lose every photo.
public class StoredImage
{
    public Guid Id { get; set; }

    public StoredImageKind Kind { get; set; }

    /// What [Data] is: always the normalised format the apps can all draw.
    public string ContentType { get; set; } = "";

    /// What the uploader sent (sniffed from the bytes, not from the name).
    public string SourceContentType { get; set; } = "";
    public int Width { get; set; }
    public int Height { get; set; }
    public byte[] Data { get; set; } = [];
    public DateTime CreatedAt { get; set; }
}

/// A portion size; the first (lowest sort order) is the default.
public class MenuItemPortion
{
    public string ItemId { get; set; } = "";
    public string Id { get; set; } = "";
    public string Label { get; set; } = "";
    public long ExtraPricePaise { get; set; }
    public string? Detail { get; set; }
    public int SortOrder { get; set; }
}

public class MenuItemAddOn
{
    public string ItemId { get; set; } = "";
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public long PricePaise { get; set; }
    public int SortOrder { get; set; }
}

public class RestaurantTable
{
    public int Number { get; set; }
    public int Seats { get; set; } = 4;
    public string Area { get; set; } = "";
    public bool IsActive { get; set; } = true;
    public long? AssignedStaffId { get; set; }
    public User? AssignedStaff { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class Order
{
    public string Id { get; set; } = "";

    /// Historical value: kept even if the table is later removed.
    public int TableNumber { get; set; }
    public DateTime CreatedAt { get; set; }
    public OrderStatus Status { get; set; }
    public OrderSource Source { get; set; }
    public string SpecialInstructions { get; set; } = "";
    public DateTime EstimatedReadyAt { get; set; }

    // Pricing snapshot at checkout: menu edits never change it.
    public long SubtotalPaise { get; set; }
    public long DiscountPaise { get; set; }
    public string? DiscountLabel { get; set; }
    public long ServiceChargePaise { get; set; }
    public int ServiceChargeBasisPoints { get; set; }
    public long TaxPaise { get; set; }
    public int TaxRateBasisPoints { get; set; }
    public string TaxName { get; set; } = "Taxes";
    public long TotalPaise { get; set; }
    public string? OfferCode { get; set; }

    /// Replays of the same submission return this order.
    public string? IdempotencyKey { get; set; }

    /// The guest session that placed it (guests only see their own orders).
    public Guid? GuestSessionId { get; set; }
    public long? CreatedByUserId { get; set; }
    public string CancelReason { get; set; } = "";
    public int? FeedbackRating { get; set; }
    public string? FeedbackComment { get; set; }
    public DateTime? FeedbackAt { get; set; }

    /// Optimistic concurrency (PostgreSQL xmin).
    public uint Version { get; set; }

    public List<OrderLine> Lines { get; set; } = [];
    public List<OrderStatusChange> History { get; set; } = [];
    public Invoice? Invoice { get; set; }
}

/// One ordered dish, frozen at checkout.
public class OrderLine
{
    public long Id { get; set; }
    public string OrderId { get; set; } = "";
    public int LineNo { get; set; }
    public string ItemId { get; set; } = "";
    public string Name { get; set; } = "";
    public string Image { get; set; } = "";
    public bool IsVeg { get; set; }
    public long UnitPricePaise { get; set; }
    public int Quantity { get; set; }
    public List<string> Options { get; set; } = [];
    public string CategoryId { get; set; } = "";
    public string CategoryName { get; set; } = "";

    // The raw choices, kept for kitchens and reports.
    public string? PortionId { get; set; }
    public SpiceLevel? Spice { get; set; }
    public List<string> AddOnIds { get; set; } = [];
}

public class OrderStatusChange
{
    public long Id { get; set; }
    public string OrderId { get; set; } = "";
    public OrderStatus Status { get; set; }
    public DateTime At { get; set; }
    public long? ChangedByUserId { get; set; }
    public string ChangedByName { get; set; } = "";
    public string Reason { get; set; } = "";
}

/// The bill for one order: the order's pricing snapshot plus the payment and
/// refund records. Its status is derived from those records only.
public class Invoice
{
    public string Id { get; set; } = "";
    public string BillNumber { get; set; } = "";
    public string OrderId { get; set; } = "";
    public Order Order { get; set; } = null!;
    public int TableNumber { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public long SubtotalPaise { get; set; }
    public long DiscountPaise { get; set; }
    public string? DiscountLabel { get; set; }
    public long ServiceChargePaise { get; set; }
    public int ServiceChargeBasisPoints { get; set; }
    public long TaxPaise { get; set; }
    public int TaxRateBasisPoints { get; set; }
    public string TaxName { get; set; } = "Taxes";
    public long TotalPaise { get; set; }

    // Restaurant details printed on the bill, frozen at creation.
    public string RestaurantName { get; set; } = "";
    public string RestaurantPhone { get; set; } = "";
    public string RestaurantEmail { get; set; } = "";
    public string RestaurantAddress { get; set; } = "";
    public string RestaurantTaxRegistration { get; set; } = "";
    public string ReceiptFooter { get; set; } = "";

    public bool IsVoid { get; set; }
    public string VoidReason { get; set; } = "";
    public DateTime? VoidedAt { get; set; }

    /// Nothing left to pay (or void). Kept in step with the payment records
    /// by [UpdateSettled] so open bills can be queried cheaply.
    public bool IsSettled { get; set; }
    public uint Version { get; set; }

    // The guest said they will pay at the counter. Only a notice for staff:
    // it moves no money and the bill's status ignores it.
    public CounterRequestKind? CounterRequest { get; set; }
    public long? CounterRequestAmountPaise { get; set; }
    public DateTime? CounterRequestedAt { get; set; }

    public List<Payment> Payments { get; set; } = [];
    public List<Refund> Refunds { get; set; } = [];

    /// A settled bill has nothing left to collect at the counter.
    public void UpdateSettled()
    {
        IsSettled = IsVoid || OutstandingPaise == 0;
        if (IsSettled) ClearCounterRequest();
    }

    public void ClearCounterRequest()
    {
        CounterRequest = null;
        CounterRequestAmountPaise = null;
        CounterRequestedAt = null;
    }

    public long AmountPaidPaise =>
        Payments.Where(p => p.Status == PaymentStatus.Succeeded).Sum(p => p.AmountPaise);

    public long AmountRefundedPaise =>
        Refunds.Where(r => r.Status == RefundStatus.Processed).Sum(r => r.AmountPaise);

    public long PendingPaise =>
        Payments.Where(p => p.Status == PaymentStatus.Pending).Sum(p => p.AmountPaise);

    /// Still owed. Refunds never re-open a balance.
    public long OutstandingPaise =>
        IsVoid ? 0 : Math.Max(0, TotalPaise - AmountPaidPaise);

    /// What may be charged now without risking an overpayment.
    public long PayableNowPaise => Math.Max(0, OutstandingPaise - PendingPaise);
}

public class Payment
{
    public string Id { get; set; } = "";
    public string InvoiceId { get; set; } = "";
    public Invoice Invoice { get; set; } = null!;
    public string OrderId { get; set; } = "";
    public long AmountPaise { get; set; }

    /// The restaurant's currency when the payment was made.
    public string Currency { get; set; } = Currencies.Default;
    public PaymentMethod Method { get; set; }

    /// Display-only detail of the method, e.g. `Scan & Pay`, `Credit` or a
    /// bank name. Never card numbers, CVVs, PINs or passwords: the API has
    /// no field that takes them.
    public string MethodDetail { get; set; } = "";
    public PaymentStatus Status { get; set; }
    public string Provider { get; set; } = "";
    public string? ProviderOrderId { get; set; }

    /// A gateway's own id for the payment that settled this one (Cashfree's
    /// `cf_payment_id`). One gateway payment settles one record at most.
    public string? ProviderPaymentId { get; set; }

    /// When a gateway order stops taking payment (the guest's time to pay).
    public DateTime? ExpiresAt { get; set; }

    /// Provider payment id, or a reference entered at the counter.
    public string Reference { get; set; } = "";
    public string FailureReason { get; set; } = "";
    public string IdempotencyKey { get; set; } = "";

    /// A demo payment (the simulator, or a counter payment recorded in demo
    /// mode): no money moved.
    public bool IsSimulated { get; set; }
    public long? RecordedByUserId { get; set; }
    public string RecordedByName { get; set; } = "";
    public Guid? GuestSessionId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    /// When the provider (or the counter) confirmed the outcome.
    public DateTime? ConfirmedAt { get; set; }

    /// UPI to the restaurant: when the guest said they had paid. That is only
    /// a claim; the payment stays pending until a cashier (or a connected
    /// verifier) confirms the money arrived.
    public DateTime? ClaimedAt { get; set; }
}

public class Refund
{
    public string Id { get; set; } = "";
    public string InvoiceId { get; set; } = "";
    public string PaymentId { get; set; } = "";
    public Payment Payment { get; set; } = null!;
    public long AmountPaise { get; set; }
    public string Reason { get; set; } = "";
    public RefundStatus Status { get; set; }
    public string Reference { get; set; } = "";
    public bool IsSimulated { get; set; }
    public long? ProcessedByUserId { get; set; }
    public string ProcessedByName { get; set; } = "";
    public string IdempotencyKey { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}

public class AuditLog
{
    public long Id { get; set; }
    public DateTime At { get; set; }
    public long? ActorId { get; set; }
    public string ActorName { get; set; } = "";
    public string ActorRole { get; set; } = "";

    /// Machine-readable action, e.g. `order.status`.
    public string Action { get; set; } = "";
    public string Summary { get; set; } = "";
    public string TargetId { get; set; } = "";
}

/// A stocked ingredient or supply. Quantities change only through recorded
/// movements; no recipe consumption is assumed.
public class InventoryItem
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Unit { get; set; } = "";
    public decimal Quantity { get; set; }
    public decimal ReorderLevel { get; set; }
    public string Supplier { get; set; } = "";
    public List<string> LinkedDishIds { get; set; } = [];
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public class StockMovement
{
    public long Id { get; set; }
    public string ItemId { get; set; } = "";
    public decimal Change { get; set; }
    public decimal Balance { get; set; }
    public string Reason { get; set; } = "";
    public DateTime At { get; set; }
    public long? ByUserId { get; set; }
    public string ByName { get; set; } = "";
}

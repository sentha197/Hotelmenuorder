using System.Text.Json.Serialization;

namespace DineQR.Api.Contracts;

// Response shapes match the Flutter models' fromJson keys (dineqr_core), so
// both apps parse them with the models they already have. Money is integer
// paise and times are UTC ISO-8601.

// ------------------------------------------------------------------- menu

public sealed record CategoryDto(
    string Id,
    string Label,
    [property: JsonPropertyName("cover")] string Cover,
    [property: JsonPropertyName("sort")] int Sort,
    bool Active);

public sealed record PortionDto(string Id, string Label, long? Extra, string? Detail);

public sealed record AddOnDto(string Id, string Name, long Price);

/// A dish as the app's MenuItem.toJson writes it. That method leaves out
/// keys at their default (e.g. `available` when true), so every property
/// has the app's default here.
public sealed record MenuItemDto
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string Category { get; init; } = "";
    public string Description { get; init; } = "";
    [JsonPropertyName("short")] public string Short { get; init; } = "";
    public long Price { get; init; }
    public string Image { get; init; } = "";
    public List<string>? Gallery { get; init; }
    public bool Veg { get; init; }
    public double Rating { get; init; }
    [JsonPropertyName("reviews")] public int Reviews { get; init; }
    public bool Popular { get; init; }
    public bool Special { get; init; }
    public bool Featured { get; init; }
    public bool Spicy { get; init; }
    public string DefaultSpice { get; init; } = "medium";
    public List<PortionDto>? Portions { get; init; }
    public List<AddOnDto>? AddOns { get; init; }
    [JsonPropertyName("prep")] public int Prep { get; init; } = 15;
    public bool Available { get; init; } = true;
    public bool Archived { get; init; }
}

/// [Promotions]: special offers and combos (guests get only those live
/// today; staff get all of them).
public sealed record MenuDto(
    List<CategoryDto> Categories,
    List<MenuItemDto> Items,
    List<PromotionDto>? Promotions = null);

public sealed record PromotionItemDto(string ItemId, int Quantity = 1);

/// A special offer (`kind: special`: [DiscountType] `percent` or `flat`
/// and its [Value], basis points or paise, off each unit of every dish in
/// [Items]) or a combo (`kind: combo`: [Items] with quantities, sold
/// together for [ComboPrice] paise). Dates are restaurant days, both
/// included. [Limit] and [Used] (orders) are sent to staff only.
public sealed record PromotionDto(
    string Id,
    string Kind,
    string Title,
    string? Description,
    string? Image,
    DateOnly? StartsOn,
    DateOnly? EndsOn,
    bool Active,
    List<PromotionItemDto>? Items,
    string? DiscountType = null,
    int? Value = null,
    long? ComboPrice = null,
    int? Limit = null,
    int? Used = null,
    int? Sort = null);

public sealed record ActiveRequest(bool Active);

public sealed record AvailabilityRequest(bool? Available, bool? Archived);

// --------------------------------------------------------- settings/tables

/// A coupon. Dates are restaurant days, both included; [Limit] and [Used]
/// (orders) are sent to staff only.
public sealed record OfferDto(
    string Code,
    string Title,
    string Type,
    int Value,
    long? Min,
    long? Max,
    bool Active,
    DateOnly? StartsOn = null,
    DateOnly? EndsOn = null,
    int? Limit = null,
    int? Used = null);

public sealed record SettingsDto(
    string Name,
    string Phone,
    string Email,
    string Address,
    string TaxReg,
    string TaxName,
    int TaxRate,
    int ServiceRate,
    int UtcOffset,
    bool Partial,
    List<string> Methods,
    string Footer,
    bool ShowSoldOut,
    bool AutoUnavailable,
    int PrepBuffer,
    // Coupons. Apps from before the Offers section save them with the
    // settings; a save without them (current apps) leaves them alone.
    List<OfferDto>? Offers,
    // ISO code (`INR`). Always sent; a save without it keeps the current one.
    string? Currency = null,
    bool? Takeaway = null,
    // The same setting under its name from before takeaway was renamed from
    // "parcel": still served to app versions that read it, and accepted from
    // those that send it. Neither key in a save keeps the current value.
    bool? Parcel = null,
    // `demo` or `live`. Always sent; a save without it (apps from before
    // payment modes) keeps the current mode.
    string? PaymentMode = null,
    // Read only (saved with PUT /admin/network-access): whether dine-in
    // guests must be on the restaurant's Wi-Fi, and its name as a hint.
    // The authorised addresses are never sent here.
    DineInWifiDto? Wifi = null);

/// What guests are told about the dine-in Wi-Fi restriction.
public sealed record DineInWifiDto(bool Enabled, string Ssid, bool Takeaway);

// ------------------------------------------------------ network access

/// An authorised network: an address, a range or a dynamic-DNS hostname.
/// [Resolved]: a hostname's current addresses (staff view only).
public sealed record AuthorizedNetworkDto(string Value, string? Label, List<string>? Resolved = null);

public sealed record NetworkAccessSettingsDto(
    bool Enabled,
    string? Ssid,
    bool RestrictTakeaway,
    List<AuthorizedNetworkDto>? Networks);

/// What the server sees for the caller's own request: the [Address] it
/// checks (from [Source]), whether it is authorised, the proxy [Headers]
/// that came with it, and what to authorise for this device
/// ([SuggestedEntry]). [Consistent] is false when edge headers name another
/// client address: the deployment then reports a proxy's address.
public sealed record NetworkCheckDto(
    string? Address,
    string Source,
    bool Matches,
    string? MatchedBy,
    bool Private,
    bool SharedCarrier,
    bool Consistent,
    Dictionary<string, string> Headers,
    string? SuggestedEntry);

public sealed record NetworkAccessViewDto(
    bool Enabled,
    string Ssid,
    bool RestrictTakeaway,
    List<AuthorizedNetworkDto> Networks,
    NetworkCheckDto You);

/// A guest's own check: [Required] is false when the restriction does not
/// cover the session (a failed check is a 403 instead).
public sealed record GuestNetworkAccessDto(bool Required, bool Allowed);

public sealed record TableDto(int Number, int Seats, string Area, bool Active, string? Server);

/// What a guest may know about a table: the welcome screen shows its seats.
public sealed record PublicTableDto(int Number, bool Active, int Seats);

public sealed record AssignTableRequest(string? StaffId);

// ------------------------------------------------------------------- auth

public sealed record LoginRequest(string Email, string Password);

public sealed record RefreshRequest(string RefreshToken);

public sealed record StaffDto(
    string Id,
    string Name,
    string Email,
    string Role,
    bool Active,
    DateTime CreatedAt,
    DateTime? LastLogin,
    List<string> Permissions,
    bool CustomAccess = false,
    string? RoleTitle = null);

public sealed record AuthResponse(
    string AccessToken,
    DateTime AccessTokenExpiresAt,
    string RefreshToken,
    DateTime SessionExpiresAt,
    StaffDto Staff);

public sealed record GuestSessionRequest(string QrPayload);

/// [TableNumber] is 0 for a takeaway session; [OrderType] says so explicitly
/// (`dineIn` or `takeaway`).
public sealed record GuestSessionResponse(string GuestToken, int TableNumber, DateTime ExpiresAt, string OrderType);

/// [RoleTitle] names a `custom` role (2 to 30 characters) and is ignored for
/// every other role.
public sealed record CreateStaffRequest(string Name, string Email, string Role, string Password, string? RoleTitle = null);

public sealed record UpdateStaffRequest(string? Name, string? Role, bool? Active, string? RoleTitle = null);

/// [Permissions] replaces what the person's role allows; null goes back to
/// the role's defaults.
public sealed record UpdateStaffAccessRequest(List<string>? Permissions);

public sealed record PasswordRequest(string Password);

public sealed record ChangeOwnPasswordRequest(string CurrentPassword, string NewPassword);

// ----------------------------------------------------------------- orders

/// Options as the app's DishCustomization.toJson writes them.
public sealed record OrderOptionsRequest(string? Spice, string? Portion, List<string>? AddOns);

/// A dish ([ItemId] and its options) or a combo ([ComboId] only).
public sealed record OrderLineRequest(
    string? ItemId,
    int Quantity,
    OrderOptionsRequest? Options,
    string? ComboId = null);

/// [OrderType] (`dineIn` or `takeaway`) is the type the app showed. Guests
/// order for their session, so it must match it; staff use it to place a
/// takeaway order, which has no [TableNumber] (apps from before the type
/// was sent use table 0 instead).
public sealed record PlaceOrderRequest(
    List<OrderLineRequest> Lines,
    string? Instructions,
    string? OfferCode,
    string IdempotencyKey,
    int? TableNumber = null,
    long? ExpectedTotal = null,
    string? OrderType = null);

/// [UnitPrice] is the full price; [Discount] the saving on the whole line
/// (a special offer, or a combo's saving), from [PromotionId]. A combo line
/// has [ComboId] and lists its dishes in [ComboItems].
public sealed record OrderLineDto(
    string ItemId,
    string Name,
    string Image,
    bool IsVeg,
    long UnitPrice,
    int Quantity,
    List<string> Options,
    string CategoryId,
    string CategoryName,
    string? ComboId = null,
    List<ComboPartDto>? ComboItems = null,
    long? Discount = null,
    string? DiscountLabel = null,
    string? PromotionId = null);

public sealed record ComboPartDto(string ItemId, string Name, int Quantity);

/// One saving on a bill: `kind` `special`, `combo` or `coupon`, `ref` the
/// promotion id or coupon code, `amount` in paise.
public sealed record DiscountLineDto(string Kind, string Label, long Amount, string? Ref);

public sealed record FeedbackDto(int Rating, string Comment, DateTime SubmittedAt);

public sealed record OrderDto(
    string Id,
    [property: JsonPropertyName("table")] int Table,
    // `dineIn` or `takeaway` (table 0).
    string Type,
    DateTime CreatedAt,
    List<OrderLineDto> Lines,
    long Subtotal,
    long Discount,
    string? DiscountLabel,
    [property: JsonPropertyName("service")] long Service,
    int ServiceRate,
    long Tax,
    long Total,
    int TaxRate,
    string TaxName,
    [property: JsonPropertyName("instructions")] string Instructions,
    string Status,
    Dictionary<string, DateTime> StatusTimes,
    DateTime ReadyAt,
    FeedbackDto? Feedback,
    string Source,
    string CancelReason,
    string? InvoiceId,
    // What [Discount] is made of; absent when there is none.
    List<DiscountLineDto>? Discounts = null);

public sealed record StatusChangeRequest(string Target, string? Reason);

public sealed record FeedbackRequest(int Rating, string? Comment);

// ---------------------------------------------------------------- billing

public sealed record AmountsDto(
    long Subtotal,
    long Discount,
    string? DiscountLabel,
    [property: JsonPropertyName("service")] long Service,
    int ServiceRate,
    long Tax,
    long Total,
    int TaxRate,
    string TaxName,
    List<DiscountLineDto>? Discounts = null);

public sealed record RestaurantSnapshotDto(
    string Name,
    string Phone,
    string Email,
    string Address,
    string TaxReg,
    string Footer);

public sealed record PaymentDto(
    string Id,
    [property: JsonPropertyName("invoice")] string Invoice,
    [property: JsonPropertyName("order")] string Order,
    long Amount,
    string Method,
    string Status,
    string Provider,
    DateTime CreatedAt,
    DateTime UpdatedAt,
    [property: JsonPropertyName("key")] string Key,
    [property: JsonPropertyName("ref")] string Ref,
    [property: JsonPropertyName("failure")] string Failure,
    bool Simulated,
    [property: JsonPropertyName("by")] string By,
    string Currency,
    // `demo` (no money moved) or `live`.
    string Mode,
    // Display-only detail of the method, e.g. `Scan & Pay` or a bank name.
    [property: JsonPropertyName("detail")] string Detail,
    // UPI to the restaurant: when the guest said they had paid. A claim, not
    // a payment: the status stays `pending` until staff confirm it.
    [property: JsonPropertyName("claimed")] DateTime? Claimed = null);

public sealed record RefundDto(
    string Id,
    [property: JsonPropertyName("invoice")] string Invoice,
    [property: JsonPropertyName("payment")] string Payment,
    long Amount,
    string Reason,
    string Status,
    DateTime CreatedAt,
    [property: JsonPropertyName("by")] string By,
    [property: JsonPropertyName("ref")] string Ref,
    bool Simulated);

public sealed record InvoiceDto(
    string Id,
    [property: JsonPropertyName("number")] string Number,
    [property: JsonPropertyName("order")] string Order,
    [property: JsonPropertyName("table")] int Table,
    string Type,
    DateTime CreatedAt,
    List<OrderLineDto> Lines,
    AmountsDto Amounts,
    RestaurantSnapshotDto Restaurant,
    List<PaymentDto> Payments,
    List<RefundDto> Refunds,
    [property: JsonPropertyName("void")] bool Void,
    string VoidReason,
    // Derived on the server too, for clients that do not compute them.
    string Status,
    long Paid,
    long Outstanding,
    long PayableNow,
    // Set while the guest has said they will pay at the counter.
    CounterRequestDto? CounterRequest);

/// The guest will pay [Amount] at the counter, in `cash` or by any method
/// there (`counter`).
public sealed record CounterRequestDto(string Kind, long Amount, DateTime At);

/// [Amount] defaults to everything payable now.
public sealed record CounterRequestBody(string Kind, long? Amount);

public sealed record PaymentIntentRequest(
    string InvoiceId,
    long Amount,
    string Method,
    string IdempotencyKey,
    string? MethodDetail = null);

/// What the app opens the provider checkout with.
public sealed record PaymentIntentResponse(
    PaymentDto Payment,
    string Provider,
    bool Simulated,
    string? ProviderOrderId,
    string? KeyId,
    long Amount,
    string Currency,
    string Mode,
    // The bill with the new payment on it (newer servers).
    InvoiceDto? Invoice = null);

/// `apps` (UPI app links) or `qr` (a QR code).
public sealed record UpiCheckoutRequest(string? Channel);

/// What the guest pays a gateway UPI payment with: [Links] by app (`default`
/// is a plain `upi://pay` link any UPI app opens; `gpay`, `phonepe`, `paytm`,
/// `bhim` open that app), or a QR code: [QrImage] (`data:image/png;base64,...`)
/// or [QrText] (a `upi://pay` link the app draws as a QR code). All carry the
/// exact amount, checked by the server. The payment is confirmed by the
/// gateway, never by the app.
public sealed record UpiCheckoutDto(
    PaymentDto Payment,
    IReadOnlyDictionary<string, string> Links,
    string QrImage,
    DateTime? ExpiresAt,
    string QrText);

public sealed record PaymentConfirmRequest(
    string? ProviderPaymentId,
    string? ProviderOrderId,
    string? Signature,
    /// Demo simulator only: `success`, `failure` or `cancel`.
    string? SimulatedOutcome);

public sealed record CounterPaymentRequest(
    long Amount,
    string Method,
    string? Reference,
    string IdempotencyKey,
    string? MethodDetail = null);

public sealed record RefundRequest(long Amount, string Reason, string IdempotencyKey);

public sealed record PaymentResultDto(PaymentDto Payment, InvoiceDto Invoice);

// ------------------------------------------------ UPI to the restaurant

/// What a guest (or a cashier) needs to pay the restaurant by UPI. Only the
/// public payee details; [VerificationMode] is the one in effect (`manual`
/// unless a verifier is really connected).
public sealed record UpiConfigDto(
    bool Enabled,
    string UpiId,
    string PayeeName,
    string QrImage,
    string VerificationMode);

/// The owner's view of the payment settings and what this server can do.
public sealed record PaymentSettingsDto(
    bool Enabled,
    string UpiId,
    string PayeeName,
    string QrImage,
    string VerificationMode,
    // True only when a bank or payment-provider integration is connected.
    bool AutomaticVerificationAvailable,
    // Guests are offered UPI right now: switched on and fully set up.
    bool Ready);

/// [QrImage] is "" (none), the saved value, or the URL of an image uploaded
/// to `/admin/uploads/upi-qr`.
public sealed record PaymentSettingsRequest(
    bool Enabled,
    string? UpiId,
    string? PayeeName,
    string? QrImage,
    string? VerificationMode);

/// Starts a UPI payment to the restaurant. The amount is checked against the
/// bill's balance on the server.
public sealed record UpiStartRequest(string InvoiceId, long Amount, string IdempotencyKey);

/// The guest says they have paid, optionally with the UPI transaction ID.
public sealed record UpiClaimRequest(string? Reference);

/// A cashier confirms the money arrived, with the bank's UPI transaction ID.
public sealed record UpiVerifyRequest(string? Reference);

public sealed record UpiRejectRequest(string? Reason);

// --------------------------------------------------------- staff/audit/stock

public sealed record AuditDto(
    string Id,
    DateTime At,
    [property: JsonPropertyName("actor")] string Actor,
    string Name,
    string Role,
    string Action,
    string Summary,
    [property: JsonPropertyName("target")] string Target);

public sealed record InventoryItemDto(
    string Id,
    string Name,
    string Unit,
    [property: JsonPropertyName("qty")] decimal Qty,
    [property: JsonPropertyName("reorder")] decimal Reorder,
    [property: JsonPropertyName("updated")] DateTime Updated,
    string Supplier,
    [property: JsonPropertyName("dishes")] List<string> Dishes);

public sealed record StockMovementDto(
    string Id,
    [property: JsonPropertyName("item")] string Item,
    decimal Change,
    decimal Balance,
    string Reason,
    DateTime At,
    string By);

public sealed record InventoryDto(List<InventoryItemDto> Items, List<StockMovementDto> Movements);

public sealed record InventoryItemRequest(
    string Name,
    string Unit,
    decimal Reorder,
    string? Supplier,
    List<string>? Dishes,
    decimal? InitialQuantity);

public sealed record AdjustmentRequest(decimal Change, string Reason);

/// The stored URL of an uploaded photo, saved on the menu item afterwards.
public sealed record UploadedImageDto(string Url);

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
    public bool Spicy { get; init; }
    public string DefaultSpice { get; init; } = "medium";
    public List<PortionDto>? Portions { get; init; }
    public List<AddOnDto>? AddOns { get; init; }
    [JsonPropertyName("prep")] public int Prep { get; init; } = 15;
    public bool Available { get; init; } = true;
    public bool Archived { get; init; }
}

public sealed record MenuDto(List<CategoryDto> Categories, List<MenuItemDto> Items);

public sealed record AvailabilityRequest(bool? Available, bool? Archived);

// --------------------------------------------------------- settings/tables

public sealed record OfferDto(
    string Code,
    string Title,
    string Type,
    int Value,
    long? Min,
    long? Max,
    bool Active);

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
    List<OfferDto> Offers,
    string Currency = "INR",
    bool? Takeaway = null,
    // The same setting under its name from before takeaway was renamed from
    // "parcel": still served to app versions that read it, and accepted from
    // those that send it. Neither key in a save keeps the current value.
    bool? Parcel = null);

public sealed record TableDto(int Number, int Seats, string Area, bool Active, string? Server);

public sealed record PublicTableDto(int Number, bool Active);

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
    List<string> Permissions);

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

public sealed record CreateStaffRequest(string Name, string Email, string Role, string Password);

public sealed record UpdateStaffRequest(string? Name, string? Role, bool? Active);

public sealed record PasswordRequest(string Password);

public sealed record ChangeOwnPasswordRequest(string CurrentPassword, string NewPassword);

// ----------------------------------------------------------------- orders

/// Options as the app's DishCustomization.toJson writes them.
public sealed record OrderOptionsRequest(string? Spice, string? Portion, List<string>? AddOns);

public sealed record OrderLineRequest(string ItemId, int Quantity, OrderOptionsRequest? Options);

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

public sealed record OrderLineDto(
    string ItemId,
    string Name,
    string Image,
    bool IsVeg,
    long UnitPrice,
    int Quantity,
    List<string> Options,
    string CategoryId,
    string CategoryName);

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
    string? InvoiceId);

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
    string TaxName);

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
    long PayableNow);

public sealed record PaymentIntentRequest(
    string InvoiceId,
    long Amount,
    string Method,
    string IdempotencyKey);

/// What the app opens the provider checkout with.
public sealed record PaymentIntentResponse(
    PaymentDto Payment,
    string Provider,
    bool Simulated,
    string? ProviderOrderId,
    string? KeyId,
    long Amount,
    string Currency);

public sealed record PaymentConfirmRequest(
    string? ProviderPaymentId,
    string? ProviderOrderId,
    string? Signature,
    /// Development simulator only: `success`, `failure` or `cancel`.
    string? SimulatedOutcome);

public sealed record CounterPaymentRequest(
    long Amount,
    string Method,
    string? Reference,
    string IdempotencyKey);

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

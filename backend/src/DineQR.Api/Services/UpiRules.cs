using System.Text.RegularExpressions;
using DineQR.Api.Domain;

namespace DineQR.Api.Services;

/// The rules for UPI payments straight to the restaurant's own account. The
/// apps mirror the validation (dineqr_core `UpiSettings`) so a mistake is
/// caught before a request is sent, but the server decides.
public static partial class UpiRules
{
    /// Stored as [Payment.Provider] for a payment the guest makes to the
    /// restaurant's own UPI ID. The server never moves this money: it records
    /// only what a cashier (or a connected verifier) has confirmed.
    public const string Provider = "UPI direct";

    /// An attempt the guest started but never said they had made is dropped
    /// after this long, so an abandoned one cannot block the bill (counter
    /// payments included). A claimed payment waits for a cashier instead.
    public static readonly TimeSpan AttemptWindow = TimeSpan.FromMinutes(15);

    // handle@bank, lower case: letters, digits, '.', '-' and '_' before the
    // '@', letters and digits after it.
    [GeneratedRegex(@"^[a-z0-9][a-z0-9._-]{1,63}@[a-z][a-z0-9]{1,31}$")]
    private static partial Regex IdPattern();

    // A bank's UPI transaction reference (usually 12 digits), upper case.
    [GeneratedRegex(@"^[A-Z0-9][A-Z0-9._/-]{5,39}$")]
    private static partial Regex ReferencePattern();

    public static string NormalizeId(string? id) => (id ?? "").Trim().ToLowerInvariant();

    public static bool IsValidId(string id) => IdPattern().IsMatch(id);

    public static string NormalizeName(string? name) => (name ?? "").Trim();

    public static bool IsValidName(string name) =>
        name.Length is >= 2 and <= 60 && !name.Any(char.IsControl) && name.IndexOfAny(['<', '>']) < 0;

    public static string NormalizeReference(string? reference) => (reference ?? "").Trim().ToUpperInvariant();

    public static bool IsValidReference(string reference) => ReferencePattern().IsMatch(reference);

    /// Whether guests can be offered UPI: switched on and fully set up.
    public static bool IsReady(RestaurantSettings settings) =>
        settings.UpiEnabled && IsValidId(settings.UpiId) && IsValidName(settings.UpiPayeeName);

    /// Whether [payment] is a UPI payment to the restaurant's own account.
    public static bool IsDirect(Payment payment) => payment.Provider == Provider;
}

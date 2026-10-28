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

    /// The handles Google Pay gives its users' UPI IDs.
    private static readonly string[] GooglePayHandles = ["okaxis", "okhdfcbank", "okicici", "oksbi"];

    public static string NormalizeId(string? id) => (id ?? "").Trim().ToLowerInvariant();

    /// Why [id] (normalised, not empty) cannot take payments, or null when
    /// it looks right.
    public static string? IdProblem(string id)
    {
        if (!IdPattern().IsMatch(id)) return "Enter a valid UPI ID, like name@bank.";
        var handle = id[(id.IndexOf('@') + 1)..];
        var meant = MistypedGooglePayHandle(handle);
        return meant == null
            ? null
            : $"@{handle} is not a Google Pay UPI ID. Did you mean @{meant}? Copy the UPI ID from your UPI app.";
    }

    public static bool IsValidId(string id) => IdProblem(id) == null;

    /// The Google Pay handle [handle] is one typo away from (`okabi` for
    /// `oksbi`), or null. Such an ID belongs to no one: Google Pay finds no
    /// account for it and the guest cannot pay.
    private static string? MistypedGooglePayHandle(string handle) =>
        GooglePayHandles.Contains(handle) ? null : GooglePayHandles.FirstOrDefault(h => OneTypoApart(handle, h));

    /// One character replaced, added or left out, or two neighbours swapped.
    private static bool OneTypoApart(string a, string b)
    {
        if (a == b || Math.Abs(a.Length - b.Length) > 1) return false;
        var i = 0;
        while (i < a.Length && i < b.Length && a[i] == b[i]) i++;
        if (a.Length != b.Length)
        {
            return a.Length > b.Length ? a[(i + 1)..] == b[i..] : a[i..] == b[(i + 1)..];
        }
        return a[(i + 1)..] == b[(i + 1)..] ||
               (i + 1 < a.Length && a[i] == b[i + 1] && a[i + 1] == b[i] && a[(i + 2)..] == b[(i + 2)..]);
    }

    public static string NormalizeName(string? name) => (name ?? "").Trim();

    public static bool IsValidName(string name) =>
        name.Length is >= 2 and <= 60 && !name.Any(char.IsControl) && name.IndexOfAny(['<', '>']) < 0;

    public static string NormalizeReference(string? reference) => (reference ?? "").Trim().ToUpperInvariant();

    public static bool IsValidReference(string reference) => ReferencePattern().IsMatch(reference);

    /// Whether guests can be offered UPI: switched on and fully set up.
    public static bool IsReady(RestaurantSettings settings) =>
        settings.UpiEnabled && IsValidId(settings.UpiId) && IsValidName(settings.UpiPayeeName);

    /// Whether guests may pay by UPI now: it is ready and the restaurant
    /// bills in rupees (UPI moves Indian rupees only).
    public static bool IsOffered(RestaurantSettings settings) =>
        IsReady(settings) && settings.Currency == "INR";

    /// Whether [payment] is a UPI payment to the restaurant's own account.
    public static bool IsDirect(Payment payment) => payment.Provider == Provider;
}

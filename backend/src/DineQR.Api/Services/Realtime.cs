using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace DineQR.Api.Services;

/// Live notifications (`/hubs/events`). Events only say *what* changed; the
/// apps then re-read the data through the REST API, which applies every
/// permission check. Nothing private is broadcast.
///
/// Groups: `staff` (signed-in staff), `guest:{session}` (one guest's table
/// session) and `all` (menu, settings and table availability).
[Authorize]
public sealed class EventsHub : Hub
{
    public override async Task OnConnectedAsync()
    {
        var user = Context.User;
        var kind = user?.FindFirst(ClaimNames.TokenType)?.Value;
        if (kind == ClaimNames.Staff)
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, Notifier.StaffGroup);
        }
        else if (kind == ClaimNames.Guest &&
                 Guid.TryParse(user!.FindFirst(ClaimNames.Session)?.Value, out var session))
        {
            await Groups.AddToGroupAsync(Context.ConnectionId, Notifier.GuestGroup(session));
        }
        await Groups.AddToGroupAsync(Context.ConnectionId, Notifier.AllGroup);
        await base.OnConnectedAsync();
    }
}

public sealed class Notifier(IHubContext<EventsHub> hub, ILogger<Notifier> logger)
{
    public const string StaffGroup = "staff";
    public const string AllGroup = "all";

    public static string GuestGroup(Guid session) => $"guest:{session}";

    public Task OrderChanged(Order order, string change) =>
        Send(GroupsFor(order.GuestSessionId), "orders", new
        {
            orderId = order.Id,
            table = order.TableNumber,
            status = EnumNames.ToName(order.Status),
            change,
        });

    public Task BillChanged(Invoice invoice, Guid? guestSession) =>
        Send(GroupsFor(guestSession), "bills", new
        {
            invoiceId = invoice.Id,
            orderId = invoice.OrderId,
        });

    public Task MenuChanged() => Send([AllGroup], "menu", new { });

    public Task SettingsChanged() => Send([AllGroup], "settings", new { });

    public Task TablesChanged() => Send([AllGroup], "tables", new { });

    public Task InventoryChanged() => Send([StaffGroup], "inventory", new { });

    public Task StaffChanged() => Send([StaffGroup], "staff", new { });

    private static List<string> GroupsFor(Guid? guestSession) =>
        guestSession is { } session ? [StaffGroup, GuestGroup(session)] : [StaffGroup];

    private async Task Send(IReadOnlyList<string> groups, string name, object payload)
    {
        try
        {
            await hub.Clients.Groups(groups).SendAsync(name, payload);
        }
        catch (Exception error)
        {
            // A failed notification never fails the change itself; clients
            // re-read on reconnect.
            logger.LogWarning(error, "Could not send the {Event} event", name);
        }
    }
}

/// Records sensitive actions with the acting staff member. The entry is
/// saved in the same transaction as the change it describes.
public sealed class AuditTrail(AppDbContext db, TimeProvider clock)
{
    public void Record(User? actor, string action, string summary, string targetId = "") =>
        db.AuditLogs.Add(new AuditLog
        {
            At = clock.GetUtcNow().UtcDateTime,
            ActorId = actor?.Id,
            ActorName = actor?.FullName ?? "System",
            ActorRole = actor == null ? "Automatic" : RoleLabels.Of(actor.Role),
            Action = action,
            Summary = summary,
            TargetId = targetId,
        });
}

public static class RoleLabels
{
    public static string Of(StaffRole role) => role switch
    {
        StaffRole.Owner => "Owner",
        StaffRole.Manager => "Manager",
        StaffRole.Cashier => "Cashier",
        StaffRole.Kitchen => "Kitchen staff",
        StaffRole.Waiter => "Service staff",
        StaffRole.Accountant => "Accountant",
        StaffRole.Custom => "Custom role",
        _ => role.ToString(),
    };

    /// What to call [role] for a person: the owner's own name for a custom role.
    public static string Of(StaffRole role, string? title) =>
        role == StaffRole.Custom && !string.IsNullOrWhiteSpace(title) ? title : Of(role);

    public static string Of(User user) => Of(user.Role, user.RoleTitle);
}

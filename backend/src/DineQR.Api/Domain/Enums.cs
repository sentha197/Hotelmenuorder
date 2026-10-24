namespace DineQR.Api.Domain;

// Names match the Flutter app's enums (serialised in camelCase), so both
// sides read the same values.

public enum OrderStatus { Placed, Accepted, Preparing, ReadyToServe, Served, Cancelled }

/// How an order is collected. Stored as [Order.TableNumber]: a takeaway
/// order is not tied to a table, so it carries [OrderTables.Takeaway].
public enum OrderType { DineIn, Takeaway }

public static class OrderTables
{
    /// Table number of a takeaway order. Real tables start at 1, so zero is
    /// free to mean "no table" without a nullable column.
    public const int Takeaway = 0;

    public static bool IsTakeaway(int table) => table == Takeaway;

    public static OrderType TypeOf(int table) =>
        IsTakeaway(table) ? OrderType.Takeaway : OrderType.DineIn;

    /// How the table is shown on tickets and bills.
    public static string Label(int table) =>
        IsTakeaway(table) ? "Takeaway" : $"Table {table:00}";
}

public enum OrderSource { Guest, Staff }

public enum PaymentMethod { Upi, Card, NetBanking, Wallet, Cash }

public enum PaymentStatus { Pending, Succeeded, Failed, Cancelled }

/// How the restaurant takes payments. Demo: online payments go to the
/// built-in simulator and every payment (counter ones too) is recorded as a
/// demo payment; no money moves. Live: a verified payment gateway takes
/// online payments; refused while none is configured.
public enum PaymentMode { Demo, Live }

/// How a guest said they will pay at the counter: in cash, or by any
/// method the counter takes.
public enum CounterRequestKind { Cash, Counter }

/// Currencies a restaurant can bill in. All have two decimal places, so
/// amounts stay integer minor units ("paise") everywhere.
public static class Currencies
{
    public const string Default = "INR";

    private static readonly Dictionary<string, string> Symbols = new()
    {
        ["INR"] = "₹",
        ["USD"] = "$",
        ["EUR"] = "€",
        ["GBP"] = "£",
        ["AED"] = "AED ",
        ["SGD"] = "S$",
    };

    public static bool IsSupported(string code) => Symbols.ContainsKey(code);

    /// `₹1,250`, `₹472.50` or `$12.40`, for messages and the activity log.
    public static string Format(long minor, string currency)
    {
        var symbol = Symbols.GetValueOrDefault(currency, currency + " ");
        return minor % 100 == 0 ? $"{symbol}{minor / 100:N0}" : $"{symbol}{minor / 100m:N2}";
    }
}

public enum RefundStatus { Processed, Pending, Failed }

public enum DiscountType { Percent, Flat }

public enum SpiceLevel { Mild, Medium, Spicy }

public enum StaffRole { Owner, Manager, Cashier, Kitchen, Waiter, Accountant }

/// Actions a staff member may take. The server checks these on every
/// privileged request; the apps only mirror them to shape their screens.
public enum Permission
{
    ViewDashboard,
    ViewFinancials,
    ViewOrders,
    CreateOrders,
    ManageKitchen,
    ServeOrders,
    CancelOrders,
    ViewMenu,
    ManageMenu,
    ManageCategories,
    ViewTables,
    ManageTables,
    ViewBills,
    CollectPayments,
    ViewPayments,
    ReconcilePayments,
    IssueRefunds,
    ViewReports,
    ExportReports,
    ManageInventory,
    ManageStaff,
    ManageSettings,
    ViewAuditLog,
}

public static class OrderStatusRules
{
    public static readonly OrderStatus[] Flow =
    [
        OrderStatus.Placed,
        OrderStatus.Accepted,
        OrderStatus.Preparing,
        OrderStatus.ReadyToServe,
        OrderStatus.Served,
    ];

    public static OrderStatus? Next(this OrderStatus status)
    {
        var index = Array.IndexOf(Flow, status);
        return index < 0 || index == Flow.Length - 1 ? null : Flow[index + 1];
    }

    public static bool IsActive(this OrderStatus status) =>
        status is not (OrderStatus.Served or OrderStatus.Cancelled);

    /// Restaurant policy: an order can be cancelled until it is ready.
    public static bool CanCancel(this OrderStatus status) =>
        status is OrderStatus.Placed or OrderStatus.Accepted or OrderStatus.Preparing;

    public static bool CanTransitionTo(this OrderStatus status, OrderStatus target) =>
        target == status.Next() || (target == OrderStatus.Cancelled && status.CanCancel());

    /// The permission needed to move an order to [target].
    public static Permission PermissionFor(OrderStatus target) => target switch
    {
        OrderStatus.Served => Permission.ServeOrders,
        OrderStatus.Cancelled => Permission.CancelOrders,
        _ => Permission.ManageKitchen,
    };
}

/// The authoritative role matrix (docs/BACKEND_INTEGRATION.md).
public static class RolePermissions
{
    private static readonly Dictionary<StaffRole, HashSet<Permission>> Matrix = new()
    {
        [StaffRole.Owner] = [.. Enum.GetValues<Permission>()],
        [StaffRole.Manager] =
        [
            Permission.ViewDashboard, Permission.ViewOrders, Permission.CreateOrders,
            Permission.ManageKitchen, Permission.ServeOrders, Permission.CancelOrders,
            Permission.ViewMenu, Permission.ManageMenu, Permission.ManageCategories,
            Permission.ViewTables, Permission.ManageTables, Permission.ViewBills,
            Permission.CollectPayments, Permission.ViewPayments, Permission.ViewReports,
            Permission.ManageInventory, Permission.ViewAuditLog,
        ],
        [StaffRole.Cashier] =
        [
            Permission.ViewDashboard, Permission.ViewOrders, Permission.CreateOrders,
            Permission.ViewBills, Permission.CollectPayments, Permission.ViewPayments,
            Permission.ReconcilePayments, Permission.ViewTables,
        ],
        [StaffRole.Kitchen] =
        [
            Permission.ViewOrders, Permission.ManageKitchen, Permission.ViewMenu,
        ],
        [StaffRole.Waiter] =
        [
            Permission.ViewOrders, Permission.CreateOrders, Permission.ServeOrders,
            Permission.ViewMenu, Permission.ViewTables, Permission.ViewBills,
        ],
        [StaffRole.Accountant] =
        [
            Permission.ViewDashboard, Permission.ViewFinancials, Permission.ViewOrders,
            Permission.ViewBills, Permission.ViewPayments, Permission.ReconcilePayments,
            Permission.IssueRefunds, Permission.ViewReports, Permission.ExportReports,
            Permission.ViewAuditLog,
        ],
    };

    public static IReadOnlySet<Permission> For(StaffRole role) => Matrix[role];

    public static bool Can(StaffRole role, Permission permission) =>
        Matrix[role].Contains(permission);
}

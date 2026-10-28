using System.Linq.Expressions;
using DineQR.Api.Domain;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Storage.ValueConversion;

namespace DineQR.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<RestaurantSettings> Settings => Set<RestaurantSettings>();
    public DbSet<DiscountOffer> Offers => Set<DiscountOffer>();
    public DbSet<MenuCategory> Categories => Set<MenuCategory>();
    public DbSet<MenuItem> MenuItems => Set<MenuItem>();
    public DbSet<StoredImage> StoredImages => Set<StoredImage>();
    public DbSet<RestaurantTable> Tables => Set<RestaurantTable>();
    public DbSet<Order> Orders => Set<Order>();
    public DbSet<OrderLine> OrderLines => Set<OrderLine>();
    public DbSet<OrderStatusChange> OrderStatusChanges => Set<OrderStatusChange>();
    public DbSet<Invoice> Invoices => Set<Invoice>();
    public DbSet<Payment> Payments => Set<Payment>();
    public DbSet<Refund> Refunds => Set<Refund>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();
    public DbSet<InventoryItem> InventoryItems => Set<InventoryItem>();
    public DbSet<StockMovement> StockMovements => Set<StockMovement>();

    public const string OrderSequence = "order_number_seq";
    public const string InvoiceSequence = "invoice_number_seq";
    public const string PaymentSequence = "payment_number_seq";
    public const string RefundSequence = "refund_number_seq";
    public const string InventorySequence = "inventory_item_seq";

    /// Next value of one of the id sequences above (ids such as OD12345).
    public async Task<long> NextValueAsync(string sequence, CancellationToken ct = default)
    {
        var sql = sequence switch
        {
            OrderSequence => "select nextval('order_number_seq') as \"Value\"",
            InvoiceSequence => "select nextval('invoice_number_seq') as \"Value\"",
            PaymentSequence => "select nextval('payment_number_seq') as \"Value\"",
            RefundSequence => "select nextval('refund_number_seq') as \"Value\"",
            InventorySequence => "select nextval('inventory_item_seq') as \"Value\"",
            _ => throw new ArgumentOutOfRangeException(nameof(sequence), sequence, "Unknown sequence."),
        };
        return await Database.SqlQueryRaw<long>(sql).SingleAsync(ct);
    }

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.HasSequence<long>(OrderSequence).StartsAt(12345);
        b.HasSequence<long>(InvoiceSequence);
        b.HasSequence<long>(PaymentSequence);
        b.HasSequence<long>(RefundSequence);
        b.HasSequence<long>(InventorySequence);

        // The existing users table: adopted, not created. The migration adds
        // the sign-in columns it lacks without touching existing rows.
        b.Entity<User>(e =>
        {
            e.ToTable("users", t => t.ExcludeFromMigrations());
            e.Property(u => u.Id).UseIdentityAlwaysColumn();
            e.Property(u => u.FullName).HasMaxLength(150);
            e.Property(u => u.Email).HasMaxLength(255);
            e.Property(u => u.Phone).HasMaxLength(20);
            e.Property(u => u.Role).HasMaxLength(50);
            e.HasIndex(u => u.Email).IsUnique();
        });

        b.Entity<StoredImage>(e =>
        {
            e.Property(i => i.Id).ValueGeneratedNever();
            e.Property(i => i.ContentType).HasMaxLength(100);
            e.Property(i => i.SourceContentType).HasMaxLength(100);
        });

        b.Entity<RefreshToken>(e =>
        {
            e.Property(t => t.TokenHash).HasMaxLength(64);
            e.HasIndex(t => t.TokenHash).IsUnique();
            e.HasIndex(t => t.SessionId);
            e.HasOne(t => t.User).WithMany().HasForeignKey(t => t.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<RestaurantSettings>(e =>
        {
            e.ToTable("restaurant_settings", t =>
                t.HasCheckConstraint("ck_restaurant_settings_singleton", "id = 1"));
            e.Property(s => s.Id).ValueGeneratedNever();
            e.Property(s => s.Name).HasMaxLength(60);
            e.Property(s => s.TaxName).HasMaxLength(20);
            e.Property(s => s.ReceiptFooter).HasMaxLength(120);
            e.Property(s => s.Address).HasMaxLength(160);
            e.Property(s => s.Currency).HasMaxLength(3);
            e.Property(s => s.UpiId).HasMaxLength(100);
            e.Property(s => s.UpiPayeeName).HasMaxLength(60);
            e.Property(s => s.UpiQrImage).HasMaxLength(500);
            // The column keeps the name it got when takeaway was called
            // "parcel": renaming it would break whichever API version runs
            // against the database while a deploy is in progress.
            e.Property(s => s.TakeawayOrdersEnabled).HasColumnName("parcel_orders_enabled");
        });

        b.Entity<DiscountOffer>(e =>
        {
            e.ToTable("discount_offers", t =>
                t.HasCheckConstraint("ck_discount_offers_value", "value >= 0"));
            e.HasKey(o => o.Code);
            e.Property(o => o.Code).HasMaxLength(16);
            e.Property(o => o.Title).HasMaxLength(60);
        });

        b.Entity<MenuCategory>(e =>
        {
            e.ToTable("menu_categories");
            e.Property(c => c.Id).HasMaxLength(40);
            e.Property(c => c.Label).HasMaxLength(40);
        });

        b.Entity<MenuItem>(e =>
        {
            e.ToTable("menu_items", t =>
                t.HasCheckConstraint("ck_menu_items_price", "price >= 0"));
            e.Property(i => i.Id).HasMaxLength(60);
            e.Property(i => i.Name).HasMaxLength(60);
            e.Property(i => i.ShortDescription).HasMaxLength(80);
            e.Property(i => i.Description).HasMaxLength(400);
            e.HasOne(i => i.Category).WithMany().HasForeignKey(i => i.CategoryId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasMany(i => i.Portions).WithOne().HasForeignKey(p => p.ItemId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasMany(i => i.AddOns).WithOne().HasForeignKey(a => a.ItemId)
                .OnDelete(DeleteBehavior.Cascade);
            e.Ignore(i => i.IsOrderable);
        });
        b.Entity<MenuItemPortion>(e =>
        {
            e.ToTable("menu_item_portions");
            e.HasKey(p => new { p.ItemId, p.Id });
            e.Property(p => p.Id).HasMaxLength(40);
            e.Property(p => p.Label).HasMaxLength(40);
        });
        b.Entity<MenuItemAddOn>(e =>
        {
            e.ToTable("menu_item_add_ons");
            e.HasKey(a => new { a.ItemId, a.Id });
            e.Property(a => a.Id).HasMaxLength(40);
            e.Property(a => a.Name).HasMaxLength(40);
        });

        b.Entity<RestaurantTable>(e =>
        {
            e.ToTable("restaurant_tables", t =>
            {
                t.HasCheckConstraint("ck_restaurant_tables_number", "number between 1 and 999");
                t.HasCheckConstraint("ck_restaurant_tables_seats", "seats between 1 and 30");
            });
            e.HasKey(t => t.Number);
            e.Property(t => t.Number).ValueGeneratedNever();
            e.Property(t => t.Area).HasMaxLength(24);
            e.HasOne(t => t.AssignedStaff).WithMany().HasForeignKey(t => t.AssignedStaffId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        b.Entity<Order>(e =>
        {
            e.ToTable("orders", t => t.HasCheckConstraint("ck_orders_total", "total >= 0"));
            e.Property(o => o.Id).HasMaxLength(20);
            e.Property(o => o.SpecialInstructions).HasMaxLength(200);
            e.Property(o => o.CancelReason).HasMaxLength(120);
            e.Property(o => o.FeedbackComment).HasMaxLength(300);
            e.Property(o => o.IdempotencyKey).HasMaxLength(64);
            e.Property(o => o.Version).IsRowVersion();
            e.HasIndex(o => o.IdempotencyKey).IsUnique();
            e.HasIndex(o => o.CreatedAt);
            e.HasIndex(o => o.Status);
            e.HasIndex(o => o.GuestSessionId);
            e.HasIndex(o => o.TableNumber);
            e.HasMany(o => o.Lines).WithOne().HasForeignKey(l => l.OrderId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasMany(o => o.History).WithOne().HasForeignKey(h => h.OrderId)
                .OnDelete(DeleteBehavior.Cascade);
        });
        b.Entity<OrderLine>(e =>
        {
            e.ToTable("order_lines", t =>
                t.HasCheckConstraint("ck_order_lines_quantity", "quantity between 1 and 20"));
            e.HasIndex(l => new { l.OrderId, l.LineNo }).IsUnique();
        });
        b.Entity<OrderStatusChange>(e =>
        {
            e.ToTable("order_status_history");
            e.HasIndex(h => new { h.OrderId, h.At });
        });

        b.Entity<Invoice>(e =>
        {
            e.ToTable("invoices");
            e.Property(i => i.Id).HasMaxLength(20);
            e.Property(i => i.BillNumber).HasMaxLength(20);
            e.Property(i => i.Version).IsRowVersion();
            e.HasIndex(i => i.BillNumber).IsUnique();
            e.HasIndex(i => i.OrderId).IsUnique();
            e.HasIndex(i => i.CreatedAt);
            e.HasIndex(i => i.IsSettled);
            e.HasOne(i => i.Order).WithOne(o => o.Invoice)
                .HasForeignKey<Invoice>(i => i.OrderId).OnDelete(DeleteBehavior.Restrict);
            e.Ignore(i => i.AmountPaidPaise);
            e.Ignore(i => i.AmountRefundedPaise);
            e.Ignore(i => i.PendingPaise);
            e.Ignore(i => i.OutstandingPaise);
            e.Ignore(i => i.PayableNowPaise);
        });

        b.Entity<Payment>(e =>
        {
            e.ToTable("payments", t => t.HasCheckConstraint("ck_payments_amount", "amount > 0"));
            e.Property(p => p.Id).HasMaxLength(20);
            e.Property(p => p.IdempotencyKey).HasMaxLength(64);
            e.Property(p => p.Provider).HasMaxLength(40);
            e.Property(p => p.Currency).HasMaxLength(3);
            e.Property(p => p.MethodDetail).HasMaxLength(40);
            e.Property(p => p.Reference).HasMaxLength(100);
            e.Property(p => p.FailureReason).HasMaxLength(200);
            e.Property(p => p.ProviderPaymentId).HasMaxLength(64);
            e.HasIndex(p => p.IdempotencyKey).IsUnique();
            // Gateway webhooks name the order.
            e.HasIndex(p => p.ProviderOrderId).HasFilter("provider_order_id is not null");
            e.HasIndex(p => new { p.Provider, p.ProviderPaymentId }).IsUnique()
                .HasFilter("provider_payment_id is not null");
            e.HasIndex(p => p.Status);
            e.HasIndex(p => p.CreatedAt);
            // One bank transaction reference confirms one UPI payment: the
            // same reference cannot be used to confirm two payments, whether
            // by a slip or on purpose.
            e.HasIndex(p => p.Reference).IsUnique().HasDatabaseName("ix_payments_upi_reference")
                .HasFilter("provider = 'UPI direct' and status = 'succeeded'");
            e.HasOne(p => p.Invoice).WithMany(i => i.Payments).HasForeignKey(p => p.InvoiceId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<Refund>(e =>
        {
            e.ToTable("refunds", t => t.HasCheckConstraint("ck_refunds_amount", "amount > 0"));
            e.Property(r => r.Id).HasMaxLength(20);
            e.Property(r => r.IdempotencyKey).HasMaxLength(64);
            e.Property(r => r.Reason).HasMaxLength(120);
            e.HasIndex(r => r.IdempotencyKey).IsUnique();
            e.HasOne<Invoice>().WithMany(i => i.Refunds).HasForeignKey(r => r.InvoiceId)
                .OnDelete(DeleteBehavior.Restrict);
            e.HasOne(r => r.Payment).WithMany().HasForeignKey(r => r.PaymentId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        b.Entity<AuditLog>(e =>
        {
            e.ToTable("audit_logs");
            e.HasIndex(a => a.At);
            e.HasIndex(a => a.Action);
            e.HasOne<User>().WithMany().HasForeignKey(a => a.ActorId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        b.Entity<InventoryItem>(e =>
        {
            e.ToTable("inventory_items");
            e.Property(i => i.Id).HasMaxLength(20);
            e.Property(i => i.Quantity).HasPrecision(12, 3);
            e.Property(i => i.ReorderLevel).HasPrecision(12, 3);
        });
        b.Entity<StockMovement>(e =>
        {
            e.ToTable("stock_movements");
            e.Property(m => m.Change).HasPrecision(12, 3);
            e.Property(m => m.Balance).HasPrecision(12, 3);
            e.HasIndex(m => new { m.ItemId, m.At });
            e.HasOne<InventoryItem>().WithMany().HasForeignKey(m => m.ItemId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        ApplyConventions(b);
    }

    /// Money as numeric rupees, enums as their app names.
    private static void ApplyConventions(ModelBuilder b)
    {
        foreach (var entity in b.Model.GetEntityTypes())
        {
            foreach (var property in entity.GetProperties())
            {
                var type = property.ClrType;
                if ((type == typeof(long) || type == typeof(long?)) &&
                    property.Name.EndsWith("Paise", StringComparison.Ordinal))
                {
                    property.SetValueConverter(type == typeof(long) ? PaiseConverter : NullablePaiseConverter);
                    property.SetColumnType("numeric(14,2)");
                    property.SetColumnName(ToSnake(property.Name[..^"Paise".Length]));
                }
                var enumType = Nullable.GetUnderlyingType(type) ?? type;
                if (enumType.IsEnum)
                {
                    property.SetValueConverter(
                        (ValueConverter)Activator.CreateInstance(
                            typeof(EnumNameConverter<>).MakeGenericType(enumType))!);
                    property.SetMaxLength(20);
                }
            }
        }
    }

    private static readonly ValueConverter<long, decimal> PaiseConverter =
        new(p => p / 100m, r => (long)(r * 100m));

    private static readonly ValueConverter<long?, decimal?> NullablePaiseConverter =
        new(p => p == null ? null : p / 100m, r => r == null ? null : (long)(r * 100m));

    private static string ToSnake(string name) =>
        string.Concat(name.Select((c, i) =>
            char.IsUpper(c) ? (i > 0 ? "_" : "") + char.ToLowerInvariant(c) : c.ToString()));
}

/// Stores enums by their camelCase app names (`readyToServe`, `owner`).
public class EnumNameConverter<TEnum>() : ValueConverter<TEnum, string>(
    ToStore(), FromStore()) where TEnum : struct, Enum
{
    private static Expression<Func<TEnum, string>> ToStore() => v => EnumNames.ToName(v);

    private static Expression<Func<string, TEnum>> FromStore() => v => EnumNames.Parse<TEnum>(v);
}

public static class EnumNames
{
    public static string ToName<TEnum>(TEnum value) where TEnum : struct, Enum
    {
        var name = value.ToString();
        return char.ToLowerInvariant(name[0]) + name[1..];
    }

    public static TEnum Parse<TEnum>(string value) where TEnum : struct, Enum =>
        Enum.Parse<TEnum>(value, ignoreCase: true);

    public static bool TryParse<TEnum>(string? value, out TEnum result) where TEnum : struct, Enum
    {
        result = default;
        return !string.IsNullOrWhiteSpace(value) &&
               !int.TryParse(value, out _) &&
               Enum.TryParse(value, ignoreCase: true, out result) &&
               Enum.IsDefined(result);
    }
}

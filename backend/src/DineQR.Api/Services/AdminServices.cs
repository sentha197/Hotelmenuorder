using System.Text.RegularExpressions;
using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// Menu: the public menu and staff edits (same rules as the app's
/// CatalogController).
public sealed partial class MenuService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    private IQueryable<MenuItem> Items => db.MenuItems
        .Include(i => i.Category).Include(i => i.Portions).Include(i => i.AddOns).AsSplitQuery();

    /// Guests see active categories and dishes that are not archived (sold
    /// out dishes stay listed, flagged unavailable).
    public async Task<MenuDto> PublicMenuAsync(CancellationToken ct)
    {
        var categories = await db.Categories.AsNoTracking().Where(c => c.IsActive)
            .OrderBy(c => c.SortOrder).ToListAsync(ct);
        var items = await Items.AsNoTracking()
            .Where(i => !i.IsArchived && i.Category.IsActive).OrderBy(i => i.Name).ToListAsync(ct);
        return new MenuDto([.. categories.Select(c => c.ToDto())], [.. items.Select(i => i.ToDto())]);
    }

    /// Staff: everything, including archived dishes and inactive categories
    /// (any signed-in staff member: the counter POS needs the menu too).
    public async Task<MenuDto> FullMenuAsync(CancellationToken ct)
    {
        await caller.RequireStaffAsync(ct);
        var categories = await db.Categories.AsNoTracking().OrderBy(c => c.SortOrder).ToListAsync(ct);
        var items = await Items.AsNoTracking().OrderBy(i => i.Name).ToListAsync(ct);
        return new MenuDto([.. categories.Select(c => c.ToDto())], [.. items.Select(i => i.ToDto())]);
    }

    [GeneratedRegex(@"^[a-z0-9][a-z0-9_]{0,59}$")]
    private static partial Regex IdPattern();

    // A bundled asset path, or a URL. Plain http is allowed because the
    // development API serves uploads from http://localhost; deployments
    // should set ImageStorage:PublicBaseUrl to an https address.
    [GeneratedRegex(@"^(assets/images/[a-z0-9_]+\.(jpg|jpeg|png|webp)|https?://\S{1,500})$")]
    private static partial Regex ImagePattern();

    /// Creates or replaces a dish (prices apply to new orders only).
    public async Task<MenuItem> SaveItemAsync(string id, MenuItemDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageMenu, ct);
        if (!IdPattern().IsMatch(id) || dto.Id != id)
        {
            throw ApiException.Validation("id", "Dish ids use lower-case letters, digits and underscores.");
        }
        var name = (dto.Name ?? "").Trim();
        if (name.Length is < 2 or > 40) throw ApiException.Validation("name", "Dish name must be 2 to 40 characters.");
        var duplicate = await db.MenuItems.AnyAsync(
            i => i.Id != id && !i.IsArchived && i.Name.ToLower() == name.ToLower(), ct);
        if (duplicate) throw ApiException.Validation("name", $"Another dish is already called \"{name}\".");
        if ((dto.Short ?? "").Trim().Length > 60)
        {
            throw ApiException.Validation("short", "Short description can be at most 60 characters.");
        }
        if ((dto.Description ?? "").Trim().Length > 400)
        {
            throw ApiException.Validation("description", "Description can be at most 400 characters.");
        }
        if (dto.Price is < 100 or > 10_000_000)
        {
            throw ApiException.Validation("price", "Price must be between ₹1 and ₹1,00,000.");
        }
        if (dto.Prep is < 1 or > 180)
        {
            throw ApiException.Validation("prep", "Preparation time must be 1 to 180 minutes.");
        }
        if (!await db.Categories.AnyAsync(c => c.Id == dto.Category, ct))
        {
            throw ApiException.Validation("category", "Choose a category.");
        }
        var portions = dto.Portions ?? [];
        if (portions.Any(p => string.IsNullOrWhiteSpace(p.Label)))
        {
            throw ApiException.Validation("portions", "Every portion needs a name.");
        }
        if (portions.Select(p => p.Id).Distinct().Count() != portions.Count)
        {
            throw ApiException.Validation("portions", "Portion names must be unique.");
        }
        if (portions.Any(p => (p.Extra ?? 0) < 0))
        {
            throw ApiException.Validation("portions", "Portion surcharges cannot be negative.");
        }
        var addOns = dto.AddOns ?? [];
        if (addOns.Any(a => string.IsNullOrWhiteSpace(a.Name)))
        {
            throw ApiException.Validation("addOns", "Every add-on needs a name.");
        }
        if (addOns.Select(a => a.Id).Distinct().Count() != addOns.Count)
        {
            throw ApiException.Validation("addOns", "Add-on names must be unique.");
        }
        if (addOns.Any(a => a.Price is < 0 or > 1_000_000))
        {
            throw ApiException.Validation("addOns", "Add-on prices must be between ₹0 and ₹10,000.");
        }
        var images = new[] { dto.Image ?? "" }.Concat(dto.Gallery ?? []).Where(s => s.Length > 0);
        if (images.Any(image => !ImagePattern().IsMatch(image)))
        {
            throw ApiException.Validation("image", "Use one of the available photos or an https:// image URL.");
        }
        if (!EnumNames.TryParse<SpiceLevel>(dto.DefaultSpice, out var spice)) spice = SpiceLevel.Medium;

        var now = clock.GetUtcNow().UtcDateTime;
        var item = await Items.FirstOrDefaultAsync(i => i.Id == id, ct);
        var created = item == null;
        if (item == null)
        {
            item = new MenuItem { Id = id, CreatedAt = now };
            db.MenuItems.Add(item);
        }
        var oldPrice = item.PricePaise;
        item.Name = name;
        item.CategoryId = dto.Category;
        item.Description = (dto.Description ?? "").Trim();
        item.ShortDescription = (dto.Short ?? "").Trim();
        item.PricePaise = dto.Price;
        item.Image = dto.Image ?? "";
        item.Gallery = dto.Gallery ?? [];
        item.IsVeg = dto.Veg;
        item.IsPopular = dto.Popular;
        item.IsChefSpecial = dto.Special;
        item.IsFeatured = dto.Featured;
        item.HasSpiceLevel = dto.Spicy;
        item.DefaultSpice = spice;
        item.PrepMinutes = dto.Prep;
        item.IsAvailable = dto.Available;
        item.IsArchived = dto.Archived;
        item.UpdatedAt = now;
        // Ratings come from guests' feedback, never from an edit.
        item.Portions.Clear();
        item.Portions.AddRange(portions.Select((p, index) => new MenuItemPortion
        {
            Id = p.Id, Label = p.Label.Trim(), ExtraPricePaise = p.Extra ?? 0, Detail = p.Detail,
            SortOrder = index,
        }));
        item.AddOns.Clear();
        item.AddOns.AddRange(addOns.Select((a, index) => new MenuItemAddOn
        {
            Id = a.Id, Name = a.Name.Trim(), PricePaise = a.Price, SortOrder = index,
        }));
        var currency = await db.Settings.Select(s => s.Currency).SingleAsync(ct);
        string Price(long minor) => Currencies.Format(minor, currency);
        audit.Record(staff, created ? "menu.create" : "menu.update",
            created
                ? $"Added {name} at {Price(dto.Price)}"
                : oldPrice != dto.Price
                    ? $"Updated {name}: {Price(oldPrice)} → {Price(dto.Price)}"
                    : $"Updated {name}",
            id);
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
        return await Items.AsNoTracking().SingleAsync(i => i.Id == id, ct);
    }

    public async Task<MenuItem> SetFlagsAsync(string id, AvailabilityRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageMenu, ct);
        var item = await Items.FirstOrDefaultAsync(i => i.Id == id, ct) ?? throw ApiException.NotFound("Dish not found.");
        if (request.Available is { } available && available != item.IsAvailable)
        {
            item.IsAvailable = available;
            audit.Record(staff, "menu.availability",
                $"{item.Name} marked {(available ? "available" : "sold out")}", id);
        }
        if (request.Archived is { } archived && archived != item.IsArchived)
        {
            item.IsArchived = archived;
            audit.Record(staff, archived ? "menu.archive" : "menu.restore",
                $"{(archived ? "Archived" : "Restored")} {item.Name}", id);
        }
        item.UpdatedAt = clock.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
        return item;
    }

    /// Replaces the category list (labels, photos, order, active flags).
    /// A category still used by any dish (archived included) cannot be
    /// removed.
    public async Task<List<MenuCategory>> SaveCategoriesAsync(List<CategoryDto> list, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageCategories, ct);
        if (list.Count == 0) throw ApiException.Validation("categories", "Keep at least one category.");
        if (list.Select(c => c.Id).Distinct().Count() != list.Count)
        {
            throw ApiException.Validation("categories", "Category ids must be unique.");
        }
        foreach (var c in list)
        {
            var label = (c.Label ?? "").Trim();
            if (!IdPattern().IsMatch(c.Id.ToLowerInvariant()) || c.Id.Length > 40)
            {
                throw ApiException.Validation("id", "Category ids use letters, digits and underscores.");
            }
            if (label.Length is < 2 or > 24)
            {
                throw ApiException.Validation("label", "Category name must be 2 to 24 characters.");
            }
            if (list.Count(o => o.Label.Trim().Equals(label, StringComparison.OrdinalIgnoreCase)) > 1)
            {
                throw ApiException.Validation("label", $"A category called \"{label}\" already exists.");
            }
            if (c.Cover.Length > 0 && !ImagePattern().IsMatch(c.Cover))
            {
                throw ApiException.Validation("cover", "Use one of the available photos or an https:// image URL.");
            }
        }
        var existing = await db.Categories.ToListAsync(ct);
        var keep = list.Select(c => c.Id).ToHashSet();
        foreach (var removed in existing.Where(c => !keep.Contains(c.Id)))
        {
            if (await db.MenuItems.AnyAsync(i => i.CategoryId == removed.Id, ct))
            {
                throw ApiException.Conflict("categoryInUse",
                    $"\"{removed.Label}\" still has dishes. Move or delete them first.");
            }
            db.Categories.Remove(removed);
            audit.Record(staff, "category.delete", $"Deleted category {removed.Label}", removed.Id);
        }
        foreach (var (dto, index) in list.Select((c, i) => (c, i)))
        {
            var row = existing.FirstOrDefault(c => c.Id == dto.Id);
            if (row == null)
            {
                row = new MenuCategory { Id = dto.Id };
                db.Categories.Add(row);
                audit.Record(staff, "category.create", $"Added category {dto.Label.Trim()}", dto.Id);
            }
            else if (row.Label != dto.Label.Trim() || row.IsActive != dto.Active || row.CoverImage != dto.Cover)
            {
                audit.Record(staff, "category.update", $"Updated category {dto.Label.Trim()}", dto.Id);
            }
            row.Label = dto.Label.Trim();
            row.CoverImage = dto.Cover;
            row.IsActive = dto.Active;
            row.SortOrder = index;
        }
        await db.SaveChangesAsync(ct);
        await notifier.MenuChanged();
        return await db.Categories.AsNoTracking().OrderBy(c => c.SortOrder).ToListAsync(ct);
    }
}

/// Restaurant settings, offers and tables.
public sealed partial class SettingsService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    PaymentProviders providers,
    TimeProvider clock)
{
    /// The payment set-up the apps need (no secrets): the mode and the
    /// provider taking online payments now, and whether live mode can be
    /// chosen. `provider`, `available` and `simulated` keep their meaning
    /// for apps from before payment modes.
    public async Task<object> PaymentConfigAsync(CancellationToken ct)
    {
        var settings = await db.Settings.AsNoTracking()
            .Select(s => new { s.PaymentMode, s.Currency }).SingleAsync(ct);
        var current = providers.For(settings.PaymentMode);
        return new
        {
            provider = current.Name,
            available = current.IsAvailable,
            simulated = current.IsSimulated,
            keyId = current.PublicKeyId,
            mode = EnumNames.ToName(settings.PaymentMode),
            currency = settings.Currency,
            liveProvider = providers.Live.Name,
            liveAvailable = providers.LiveAvailable,
            // Online methods guests can pay with now, and in live mode
            // (Cashfree: UPI only).
            methods = OnlineMethods(current),
            liveMethods = OnlineMethods(providers.LiveAvailable ? providers.Live : null),
        };
    }

    private static string[] OnlineMethods(IPaymentProvider? provider) =>
        provider is { IsAvailable: true }
            ? Enum.GetValues<PaymentMethod>()
                .Where(m => m != PaymentMethod.Cash && provider.Supports(m))
                .Select(EnumNames.ToName)
                .ToArray()
            : [];

    public async Task<SettingsDto> PublicAsync(CancellationToken ct)
    {
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var offers = await db.Offers.AsNoTracking().Where(o => o.IsActive).ToListAsync(ct);
        return settings.ToDto(offers);
    }

    public async Task<SettingsDto> ForStaffAsync(CancellationToken ct)
    {
        await caller.RequireStaffAsync(ct);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var offers = await db.Offers.AsNoTracking().ToListAsync(ct);
        return settings.ToDto(offers);
    }

    [GeneratedRegex(@"^[^@\s]+@[^@\s]+\.[^@\s]+$")]
    private static partial Regex EmailPattern();

    [GeneratedRegex(@"^[0-9+()\-\s]{6,20}$")]
    private static partial Regex PhonePattern();

    [GeneratedRegex(@"^[A-Za-z0-9\-]{5,20}$")]
    private static partial Regex TaxIdPattern();

    [GeneratedRegex(@"^[A-Z0-9]{3,16}$")]
    private static partial Regex OfferCodePattern();

    /// Validates and saves settings and the full offer list (same rules as
    /// the app's SettingsController).
    public async Task<SettingsDto> SaveAsync(SettingsDto dto, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var name = (dto.Name ?? "").Trim();
        if (name.Length is < 2 or > 60) throw ApiException.Validation("name", "Restaurant name must be 2 to 60 characters.");
        if (dto.Email.Length > 0 && !EmailPattern().IsMatch(dto.Email))
        {
            throw ApiException.Validation("email", "Enter a valid email address or leave it empty.");
        }
        if (dto.Phone.Length > 0 && !PhonePattern().IsMatch(dto.Phone))
        {
            throw ApiException.Validation("phone", "Enter a valid phone number or leave it empty.");
        }
        if (dto.Address.Length > 160) throw ApiException.Validation("address", "Address can be at most 160 characters.");
        if (dto.TaxReg.Length > 0 && !TaxIdPattern().IsMatch(dto.TaxReg))
        {
            throw ApiException.Validation("taxReg", "Tax registration must be 5 to 20 letters or digits.");
        }
        var taxName = (dto.TaxName ?? "").Trim();
        if (taxName.Length is < 1 or > 20) throw ApiException.Validation("taxName", "Tax name must be 1 to 20 characters.");
        if (dto.TaxRate is < 0 or > 2800) throw ApiException.Validation("taxRate", "Tax rate must be between 0% and 28%.");
        if (dto.ServiceRate is < 0 or > 2000)
        {
            throw ApiException.Validation("serviceRate", "Service charge must be between 0% and 20%.");
        }
        if (dto.UtcOffset is < -720 or > 840) throw ApiException.Validation("utcOffset", "Choose a valid time zone.");
        if (dto.Footer.Length > 120) throw ApiException.Validation("footer", "Receipt note can be at most 120 characters.");
        if (dto.PrepBuffer is < 0 or > 60)
        {
            throw ApiException.Validation("prepBuffer", "Preparation buffer must be 0 to 60 minutes.");
        }
        var methods = new List<string>();
        foreach (var method in dto.Methods ?? [])
        {
            if (!EnumNames.TryParse<PaymentMethod>(method, out var parsed) || parsed == PaymentMethod.Cash)
            {
                throw ApiException.Validation("methods", $"Unknown online payment method \"{method}\".");
            }
            if (!methods.Contains(EnumNames.ToName(parsed))) methods.Add(EnumNames.ToName(parsed));
        }
        var offers = dto.Offers ?? [];
        foreach (var offer in offers)
        {
            if (!OfferCodePattern().IsMatch(offer.Code ?? ""))
            {
                throw ApiException.Validation("offers", "Offer codes are 3 to 16 capital letters or digits.");
            }
            if (!EnumNames.TryParse<DiscountType>(offer.Type, out var type))
            {
                throw ApiException.Validation("offers", "Offer type must be percent or flat.");
            }
            if (type == DiscountType.Percent ? offer.Value is < 1 or > 10000 : offer.Value is < 1 or > 10_000_000)
            {
                throw ApiException.Validation("offers", $"The value of {offer.Code} is out of range.");
            }
            if ((offer.Min ?? 0) < 0 || offer.Max is < 0) throw ApiException.Validation("offers", "Amounts cannot be negative.");
        }
        if (offers.Select(o => o.Code).Distinct().Count() != offers.Count)
        {
            throw ApiException.Validation("offers", "Offer codes must be unique.");
        }

        var settings = await db.Settings.SingleAsync(ct);
        var mode = settings.PaymentMode;
        if (dto.PaymentMode != null)
        {
            if (!EnumNames.TryParse(dto.PaymentMode, out mode))
            {
                throw ApiException.Validation("paymentMode", "Payment mode must be demo or live.");
            }
            // Switching to live needs the gateway; a save that keeps live
            // (after a gateway went away) still goes through.
            if (mode == PaymentMode.Live && settings.PaymentMode != PaymentMode.Live && !providers.LiveAvailable)
            {
                throw ApiException.Conflict("liveUnavailable",
                    "Live payments need a verified payment gateway, and none is configured on the server. " +
                    "The restaurant stays in demo mode.");
            }
        }
        var currency = (dto.Currency ?? settings.Currency).Trim().ToUpperInvariant();
        if (currency != settings.Currency)
        {
            if (!Currencies.IsSupported(currency))
            {
                throw ApiException.Validation("currency", $"\"{currency}\" is not a supported currency.");
            }
            if (await db.Invoices.AnyAsync(ct))
            {
                throw ApiException.Conflict("currencyLocked",
                    "The currency cannot change once bills exist: earlier bills would show the wrong currency.");
            }
        }
        settings.Name = name;
        settings.Phone = dto.Phone.Trim();
        settings.Email = dto.Email.Trim();
        settings.Address = dto.Address.Trim();
        settings.TaxRegistration = dto.TaxReg.Trim();
        settings.TaxName = taxName;
        settings.TaxRateBasisPoints = dto.TaxRate;
        settings.ServiceChargeBasisPoints = dto.ServiceRate;
        settings.UtcOffsetMinutes = dto.UtcOffset;
        settings.AllowPartialPayments = dto.Partial;
        settings.OnlineMethods = methods;
        settings.ReceiptFooter = dto.Footer.Trim();
        settings.ShowSoldOutDishes = dto.ShowSoldOut;
        settings.AutoUnavailableWhenOutOfStock = dto.AutoUnavailable;
        settings.PrepBufferMinutes = dto.PrepBuffer;
        // Apps from before the rename send only `parcel`; a save that names
        // neither must not switch takeaway off.
        settings.TakeawayOrdersEnabled = dto.Takeaway ?? dto.Parcel ?? settings.TakeawayOrdersEnabled;
        if (mode != settings.PaymentMode)
        {
            audit.Record(staff, "settings.paymentMode",
                $"Switched payments to {EnumNames.ToName(mode)} mode");
        }
        settings.PaymentMode = mode;
        settings.Currency = currency;
        settings.UpdatedAt = clock.GetUtcNow().UtcDateTime;

        var existing = await db.Offers.ToListAsync(ct);
        db.Offers.RemoveRange(existing.Where(o => offers.All(n => n.Code != o.Code)));
        foreach (var (offer, index) in offers.Select((o, i) => (o, i)))
        {
            var row = existing.FirstOrDefault(o => o.Code == offer.Code);
            if (row == null)
            {
                row = new DiscountOffer { Code = offer.Code };
                db.Offers.Add(row);
            }
            row.Title = (offer.Title ?? "").Trim();
            row.Type = EnumNames.Parse<DiscountType>(offer.Type);
            row.Value = offer.Value;
            row.MinSubtotalPaise = offer.Min ?? 0;
            row.MaxDiscountPaise = offer.Max;
            row.IsActive = offer.Active;
            row.SortOrder = index;
        }
        audit.Record(staff, "settings.update", "Updated restaurant settings and offers");
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
        return await ForStaffAsync(ct);
    }

    public async Task<PublicTableDto> PublicTableAsync(int number, CancellationToken ct)
    {
        var table = await db.Tables.AsNoTracking().FirstOrDefaultAsync(t => t.Number == number, ct)
                    ?? throw ApiException.NotFound("This QR code points to a table that does not exist.");
        return new PublicTableDto(table.Number, table.IsActive);
    }

    public async Task<List<PublicTableDto>> PublicTablesAsync(CancellationToken ct) =>
        await db.Tables.AsNoTracking().OrderBy(t => t.Number)
            .Select(t => new PublicTableDto(t.Number, t.IsActive)).ToListAsync(ct);

    /// Any signed-in staff member (orders and the kitchen show tables).
    public async Task<List<RestaurantTable>> TablesAsync(CancellationToken ct)
    {
        await caller.RequireStaffAsync(ct);
        return await db.Tables.AsNoTracking().OrderBy(t => t.Number).ToListAsync(ct);
    }

    /// Replaces the table list. Removing a table is refused while it has an
    /// open order or an unpaid bill; past orders keep their table number.
    public async Task<List<RestaurantTable>> SaveTablesAsync(List<TableDto> list, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageTables, ct);
        if (list.Select(t => t.Number).Distinct().Count() != list.Count)
        {
            throw ApiException.Validation("number", "Table numbers must be unique.");
        }
        foreach (var t in list)
        {
            if (t.Number is < 1 or > 999) throw ApiException.Validation("number", "Table numbers go from 1 to 999.");
            if (t.Seats is < 1 or > 30) throw ApiException.Validation("seats", "Seats must be between 1 and 30.");
            if ((t.Area ?? "").Trim().Length > 24) throw ApiException.Validation("area", "Area can be at most 24 characters.");
        }
        // `server`: omitted keeps the current assignment, "" clears it, an id
        // assigns it (the apps' table model may not carry assignments).
        var staffIds = list.Where(t => !string.IsNullOrEmpty(t.Server)).Select(t => ParseStaffId(t.Server))
            .ToHashSet();
        var servers = await db.Users.Where(u => staffIds.Contains(u.Id) && u.IsActive).Select(u => u.Id)
            .ToListAsync(ct);
        if (servers.Count != staffIds.Count)
        {
            throw ApiException.Validation("server", "Assign tables to active staff members only.");
        }

        var existing = await db.Tables.ToListAsync(ct);
        var now = clock.GetUtcNow().UtcDateTime;
        foreach (var removed in existing.Where(e => list.All(t => t.Number != e.Number)))
        {
            var busy = await db.Orders.AnyAsync(o => o.TableNumber == removed.Number &&
                                                    o.Status != OrderStatus.Served &&
                                                    o.Status != OrderStatus.Cancelled, ct) ||
                       await db.Invoices.AnyAsync(i => i.TableNumber == removed.Number && !i.IsSettled, ct);
            if (busy)
            {
                throw ApiException.Conflict("tableInUse",
                    $"Table {removed.Number} has open orders or unpaid bills. Close them first.");
            }
            db.Tables.Remove(removed);
            audit.Record(staff, "table.delete", $"Removed table {removed.Number}", removed.Number.ToString());
        }
        foreach (var dto in list)
        {
            var row = existing.FirstOrDefault(e => e.Number == dto.Number);
            var server = dto.Server switch
            {
                null => row?.AssignedStaffId,
                "" => (long?)null,
                var id => ParseStaffId(id),
            };
            if (row == null)
            {
                row = new RestaurantTable { Number = dto.Number, CreatedAt = now };
                db.Tables.Add(row);
                audit.Record(staff, "table.create", $"Added table {dto.Number} ({dto.Seats} seats)",
                    dto.Number.ToString());
            }
            else
            {
                if (row.IsActive != dto.Active)
                {
                    audit.Record(staff, "table.toggle",
                        $"{(dto.Active ? "Activated" : "Deactivated")} table {dto.Number}", dto.Number.ToString());
                }
                if (row.AssignedStaffId != server)
                {
                    audit.Record(staff, "table.assign",
                        server == null ? $"Cleared the server of table {dto.Number}"
                            : $"Assigned table {dto.Number} to staff {server}", dto.Number.ToString());
                }
                if (row.Seats != dto.Seats || row.Area != (dto.Area ?? "").Trim())
                {
                    audit.Record(staff, "table.update", $"Updated table {dto.Number} ({dto.Seats} seats)",
                        dto.Number.ToString());
                }
            }
            row.Seats = dto.Seats;
            row.Area = (dto.Area ?? "").Trim();
            row.IsActive = dto.Active;
            row.AssignedStaffId = server;
        }
        await db.SaveChangesAsync(ct);
        await notifier.TablesChanged();
        return await db.Tables.AsNoTracking().OrderBy(t => t.Number).ToListAsync(ct);
    }

    private static long ParseStaffId(string? id) =>
        long.TryParse(id, out var value) ? value : throw ApiException.Validation("server", "Unknown staff member.");
}

/// Staff accounts and roles (manageStaff) and the activity log.
public sealed class StaffService(
    AppDbContext db,
    CurrentCaller caller,
    IPasswordHasher<User> hasher,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    public async Task<List<User>> ListAsync(CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ManageStaff, ct);
        return await db.Users.AsNoTracking().OrderBy(u => u.Role).ThenBy(u => u.FullName).ToListAsync(ct);
    }

    /// Staff who can serve tables (for table assignment).
    public async Task<List<User>> ServersAsync(CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ViewTables, ct);
        var roles = Enum.GetValues<StaffRole>().Where(r => RolePermissions.Can(r, Permission.ServeOrders)).ToList();
        return await db.Users.AsNoTracking().Where(u => u.IsActive && roles.Contains(u.Role))
            .OrderBy(u => u.FullName).ToListAsync(ct);
    }

    private static StaffRole ParseRole(string? role) =>
        EnumNames.TryParse<StaffRole>(role, out var parsed)
            ? parsed
            : throw ApiException.Validation("role", "Unknown role.");

    public async Task<User> CreateAsync(CreateStaffRequest request, CancellationToken ct)
    {
        var actor = await caller.RequireAsync(Permission.ManageStaff, ct);
        var name = (request.Name ?? "").Trim();
        var email = AuthService.NormalizeEmail(request.Email);
        if (name.Length is < 2 or > 40) throw ApiException.Validation("name", "Name must be 2 to 40 characters.");
        if (!email.Contains('@') || !email.Contains('.') || email.Length > 255)
        {
            throw ApiException.Validation("email", "Enter a valid email address.");
        }
        if (await db.Users.AnyAsync(u => u.Email == email, ct))
        {
            throw ApiException.Validation("email", "An account with this email exists.");
        }
        var role = ParseRole(request.Role);
        StaffRules.ValidateNewPassword(request.Password);
        var now = clock.GetUtcNow().UtcDateTime;
        var user = new User
        {
            FullName = name, Email = email, Role = role, IsActive = true, CreatedAt = now, UpdatedAt = now,
        };
        user.PasswordHash = hasher.HashPassword(user, request.Password);
        // The account id is needed for the audit entry; both are saved in one
        // transaction.
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        db.Users.Add(user);
        await db.SaveChangesAsync(ct);
        audit.Record(actor, "staff.create", $"Added {name} as {RoleLabels.Of(role)}", user.Id.ToString());
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
        await notifier.StaffChanged();
        return user;
    }

    /// Owners cannot demote or deactivate themselves, and at least one active
    /// owner always remains.
    public async Task<User> UpdateAsync(long id, UpdateStaffRequest request, CancellationToken ct)
    {
        var actor = await caller.RequireAsync(Permission.ManageStaff, ct);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct) ?? throw ApiException.NotFound("Staff member not found.");
        async Task<bool> LastActiveOwner() =>
            user.Role == StaffRole.Owner && user.IsActive &&
            await db.Users.CountAsync(u => u.Role == StaffRole.Owner && u.IsActive, ct) == 1;

        if (request.Name is { } newName)
        {
            var name = newName.Trim();
            if (name.Length is < 2 or > 40) throw ApiException.Validation("name", "Name must be 2 to 40 characters.");
            user.FullName = name;
        }
        if (request.Role is { } roleName)
        {
            var role = ParseRole(roleName);
            if (role != user.Role)
            {
                if (user.Id == actor.Id) throw ApiException.Validation("role", "You cannot change your own role.");
                if (await LastActiveOwner()) throw ApiException.Validation("role", "Keep at least one active owner.");
                audit.Record(actor, "staff.role", $"{user.FullName}: {RoleLabels.Of(user.Role)} → {RoleLabels.Of(role)}",
                    user.Id.ToString());
                user.Role = role;
            }
        }
        if (request.Active is { } active && active != user.IsActive)
        {
            if (user.Id == actor.Id) throw ApiException.Validation("active", "You cannot deactivate yourself.");
            if (!active && await LastActiveOwner()) throw ApiException.Validation("active", "Keep at least one active owner.");
            user.IsActive = active;
            audit.Record(actor, active ? "staff.activate" : "staff.deactivate",
                $"{(active ? "Activated" : "Deactivated")} {user.FullName}", user.Id.ToString());
            if (!active)
            {
                // Signed-in devices lose access at their next request.
                var now = clock.GetUtcNow().UtcDateTime;
                await db.RefreshTokens.Where(t => t.UserId == user.Id && t.RevokedAt == null)
                    .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);
            }
        }
        user.UpdatedAt = clock.GetUtcNow().UtcDateTime;
        await db.SaveChangesAsync(ct);
        await notifier.StaffChanged();
        return user;
    }

    public async Task ResetPasswordAsync(long id, PasswordRequest request, CancellationToken ct)
    {
        var actor = await caller.RequireAsync(Permission.ManageStaff, ct);
        var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id, ct) ?? throw ApiException.NotFound("Staff member not found.");
        StaffRules.ValidateNewPassword(request.Password);
        user.PasswordHash = hasher.HashPassword(user, request.Password);
        user.UpdatedAt = clock.GetUtcNow().UtcDateTime;
        audit.Record(actor, "staff.password", $"Reset the password of {user.FullName}", user.Id.ToString());
        // Existing sessions of that account end.
        var now = clock.GetUtcNow().UtcDateTime;
        await db.RefreshTokens.Where(t => t.UserId == user.Id && t.RevokedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);
        await db.SaveChangesAsync(ct);
    }

    public async Task<List<AuditLog>> AuditAsync(DateTime? from, DateTime? to, string? action, int limit,
        CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ViewAuditLog, ct);
        var query = db.AuditLogs.AsNoTracking().AsQueryable();
        if (from is { } start) query = query.Where(a => a.At >= start);
        if (to is { } end) query = query.Where(a => a.At < end);
        if (!string.IsNullOrWhiteSpace(action)) query = query.Where(a => a.Action.StartsWith(action));
        return await query.OrderByDescending(a => a.At).Take(Math.Clamp(limit, 1, 1000)).ToListAsync(ct);
    }
}

/// Stock: items and recorded adjustments (manageInventory).
public sealed class InventoryService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    public async Task<InventoryDto> ListAsync(CancellationToken ct)
    {
        await caller.RequireAsync(Permission.ManageInventory, ct);
        var items = await db.InventoryItems.AsNoTracking().OrderBy(i => i.Name).ToListAsync(ct);
        var movements = await db.StockMovements.AsNoTracking().OrderByDescending(m => m.At).Take(500)
            .ToListAsync(ct);
        return new InventoryDto([.. items.Select(i => i.ToDto())], [.. movements.Select(m => m.ToDto())]);
    }

    private static void Validate(InventoryItemRequest request)
    {
        var name = (request.Name ?? "").Trim();
        if (name.Length is < 2 or > 40) throw ApiException.Validation("name", "Name must be 2 to 40 characters.");
        if ((request.Unit ?? "").Trim().Length is < 1 or > 10) throw ApiException.Validation("unit", "Enter a unit.");
        if (request.Reorder < 0) throw ApiException.Validation("reorder", "Reorder level cannot be negative.");
        if (request.InitialQuantity is < 0) throw ApiException.Validation("qty", "Stock cannot be negative.");
    }

    public async Task<InventoryItem> CreateAsync(InventoryItemRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageInventory, ct);
        Validate(request);
        var now = clock.GetUtcNow().UtcDateTime;
        var item = new InventoryItem
        {
            Id = $"ITM{await db.NextValueAsync(AppDbContext.InventorySequence, ct):D4}",
            Name = request.Name.Trim(),
            Unit = request.Unit.Trim(),
            Quantity = request.InitialQuantity ?? 0,
            ReorderLevel = request.Reorder,
            Supplier = (request.Supplier ?? "").Trim(),
            LinkedDishIds = request.Dishes ?? [],
            CreatedAt = now,
            UpdatedAt = now,
        };
        db.InventoryItems.Add(item);
        if (item.Quantity > 0)
        {
            db.StockMovements.Add(new StockMovement
            {
                ItemId = item.Id, Change = item.Quantity, Balance = item.Quantity, Reason = "Opening stock",
                At = now, ByUserId = staff.Id, ByName = staff.FullName,
            });
        }
        audit.Record(staff, "inventory.create", $"Added {item.Name} ({item.Quantity} {item.Unit})", item.Id);
        await db.SaveChangesAsync(ct);
        await notifier.InventoryChanged();
        return item;
    }

    public async Task<InventoryItem> UpdateAsync(string id, InventoryItemRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageInventory, ct);
        Validate(request);
        var item = await db.InventoryItems.FirstOrDefaultAsync(i => i.Id == id, ct)
                   ?? throw ApiException.NotFound("Item not found.");
        item.Name = request.Name.Trim();
        item.Unit = request.Unit.Trim();
        item.ReorderLevel = request.Reorder;
        item.Supplier = (request.Supplier ?? "").Trim();
        item.LinkedDishIds = request.Dishes ?? [];
        item.UpdatedAt = clock.GetUtcNow().UtcDateTime;
        audit.Record(staff, "inventory.update", $"Updated {item.Name}", item.Id);
        await db.SaveChangesAsync(ct);
        await notifier.InventoryChanged();
        return item;
    }

    /// Records a stock change. Linked dishes are marked sold out when the
    /// item runs out, and available again when restocked (if the restaurant
    /// uses that rule).
    public async Task<InventoryItem> AdjustAsync(string id, AdjustmentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageInventory, ct);
        var reason = (request.Reason ?? "").Trim();
        if (request.Change == 0) throw ApiException.Validation("change", "Enter a quantity.");
        if (reason.Length is < 3 or > 80) throw ApiException.Validation("reason", "Enter a reason.");
        var item = await db.InventoryItems.FirstOrDefaultAsync(i => i.Id == id, ct)
                   ?? throw ApiException.NotFound("Item not found.");
        var balance = decimal.Round(item.Quantity + request.Change, 3);
        if (balance < 0)
        {
            throw ApiException.Conflict("insufficientStock", $"Only {item.Quantity:0.###} {item.Unit} in stock.");
        }
        var wasOut = item.Quantity <= 0;
        var now = clock.GetUtcNow().UtcDateTime;
        item.Quantity = balance;
        item.UpdatedAt = now;
        db.StockMovements.Add(new StockMovement
        {
            ItemId = item.Id, Change = request.Change, Balance = balance, Reason = reason, At = now,
            ByUserId = staff.Id, ByName = staff.FullName,
        });
        audit.Record(staff, "inventory.adjust",
            $"{item.Name}: {(request.Change > 0 ? "+" : "")}{request.Change:0.###} {item.Unit} ({reason}) → {balance:0.###} {item.Unit}",
            item.Id);

        var menuChanged = false;
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var nowOut = balance <= 0;
        if (settings.AutoUnavailableWhenOutOfStock && wasOut != nowOut && item.LinkedDishIds.Count > 0)
        {
            var dishes = await db.MenuItems.Where(d => item.LinkedDishIds.Contains(d.Id)).ToListAsync(ct);
            foreach (var dish in dishes.Where(d => d.IsAvailable == nowOut))
            {
                dish.IsAvailable = !nowOut;
                dish.UpdatedAt = now;
                menuChanged = true;
                audit.Record(null, "menu.availability",
                    $"{dish.Name} marked {(nowOut ? "sold out" : "available")} ({item.Name} {(nowOut ? "ran out" : "restocked")})",
                    dish.Id);
            }
        }
        await db.SaveChangesAsync(ct);
        await notifier.InventoryChanged();
        if (menuChanged) await notifier.MenuChanged();
        return item;
    }
}

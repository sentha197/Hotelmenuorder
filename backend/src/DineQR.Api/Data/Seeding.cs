using System.Text.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Data;

public sealed class SeedOptions
{
    /// Import Data/Seed/initial-catalog.json into empty tables.
    public bool InitialCatalog { get; set; }

    /// Restaurant time zone for a fresh install (minutes from UTC; 330 = IST).
    public int UtcOffsetMinutes { get; set; } = 330;
}

/// One-time import of the catalogue the offline demo used to hard-code
/// (menu, categories, settings, offers, tables), exported from dineqr_core by
/// packages/dineqr_core/tool/export_seed_test.dart. Each part is imported
/// only while its table is empty, so restarts never duplicate or overwrite
/// anything. No orders, payments, staff or stock are seeded.
public static class CatalogSeeder
{
    private sealed record SeedFile(
        List<CategoryDto> Categories,
        List<MenuItemDto> Items,
        SettingsDto Settings,
        List<TableDto> Tables);

    public static async Task RunAsync(AppDbContext db, SeedOptions options, string contentRoot,
        TimeProvider clock, ILogger logger, CancellationToken ct = default)
    {
        var path = Path.Combine(contentRoot, "Data", "Seed", "initial-catalog.json");
        var seed = JsonSerializer.Deserialize<SeedFile>(await File.ReadAllTextAsync(path, ct), Json.Options)
                   ?? throw new InvalidOperationException("The seed file is empty.");
        var now = clock.GetUtcNow().UtcDateTime;
        await using var transaction = await db.Database.BeginTransactionAsync(ct);

        if (!await db.Settings.AnyAsync(ct))
        {
            var s = seed.Settings;
            db.Settings.Add(new RestaurantSettings
            {
                Name = s.Name, Phone = s.Phone, Email = s.Email, Address = s.Address,
                TaxRegistration = s.TaxReg, TaxName = s.TaxName, TaxRateBasisPoints = s.TaxRate,
                ServiceChargeBasisPoints = s.ServiceRate, UtcOffsetMinutes = options.UtcOffsetMinutes,
                AllowPartialPayments = s.Partial, OnlineMethods = [.. s.Methods], ReceiptFooter = s.Footer,
                ShowSoldOutDishes = s.ShowSoldOut, AutoUnavailableWhenOutOfStock = s.AutoUnavailable,
                PrepBufferMinutes = s.PrepBuffer, UpdatedAt = now,
            });
            logger.LogInformation("Seeded restaurant settings");
        }
        if (!await db.Offers.AnyAsync(ct) && seed.Settings.Offers is { } offers)
        {
            db.Offers.AddRange(offers.Select((o, i) => new DiscountOffer
            {
                Code = o.Code, Title = o.Title, Type = EnumNames.Parse<DiscountType>(o.Type), Value = o.Value,
                MinSubtotalPaise = o.Min ?? 0, MaxDiscountPaise = o.Max, IsActive = o.Active, SortOrder = i,
            }));
            logger.LogInformation("Seeded {Count} offers", offers.Count);
        }
        if (!await db.Categories.AnyAsync(ct) && !await db.MenuItems.AnyAsync(ct))
        {
            db.Categories.AddRange(seed.Categories.Select(c => new MenuCategory
            {
                Id = c.Id, Label = c.Label, CoverImage = c.Cover, SortOrder = c.Sort, IsActive = c.Active,
            }));
            db.MenuItems.AddRange(seed.Items.Select(i => new MenuItem
            {
                Id = i.Id, CategoryId = i.Category, Name = i.Name, Description = i.Description,
                ShortDescription = i.Short, PricePaise = i.Price, Image = i.Image, Gallery = i.Gallery ?? [],
                IsVeg = i.Veg, Rating = i.Rating, ReviewCount = i.Reviews, IsPopular = i.Popular,
                IsChefSpecial = i.Special, IsFeatured = i.Featured, HasSpiceLevel = i.Spicy,
                DefaultSpice = EnumNames.Parse<SpiceLevel>(i.DefaultSpice), PrepMinutes = i.Prep,
                IsAvailable = i.Available, IsArchived = i.Archived, CreatedAt = now, UpdatedAt = now,
                Portions = [.. (i.Portions ?? []).Select((p, n) => new MenuItemPortion
                {
                    Id = p.Id, Label = p.Label, ExtraPricePaise = p.Extra ?? 0, Detail = p.Detail, SortOrder = n,
                })],
                AddOns = [.. (i.AddOns ?? []).Select((a, n) => new MenuItemAddOn
                {
                    Id = a.Id, Name = a.Name, PricePaise = a.Price, SortOrder = n,
                })],
            }));
            logger.LogInformation("Seeded {Categories} categories and {Items} dishes",
                seed.Categories.Count, seed.Items.Count);
        }
        if (!await db.Tables.AnyAsync(ct))
        {
            db.Tables.AddRange(seed.Tables.Select(t => new RestaurantTable
            {
                Number = t.Number, Seats = t.Seats, Area = t.Area ?? "", IsActive = t.Active, CreatedAt = now,
            }));
            logger.LogInformation("Seeded {Count} tables", seed.Tables.Count);
        }
        await db.SaveChangesAsync(ct);
        await transaction.CommitAsync(ct);
    }
}

public sealed class BootstrapOptions
{
    public string? OwnerEmail { get; set; }
    public string? OwnerPassword { get; set; }
    public string OwnerName { get; set; } = "Restaurant Owner";
}

/// Creates the first owner account from configuration (user secrets or
/// environment variables, never source code) when no active owner exists.
/// Every other account is created by the owner in the admin app.
public static class OwnerBootstrapper
{
    public static async Task RunAsync(AppDbContext db, BootstrapOptions options,
        IPasswordHasher<User> hasher, TimeProvider clock, ILogger logger, CancellationToken ct = default)
    {
        if (await db.Users.AnyAsync(u => u.Role == StaffRole.Owner && u.IsActive, ct)) return;
        var email = (options.OwnerEmail ?? "").Trim().ToLowerInvariant();
        var password = options.OwnerPassword ?? "";
        if (email.Length == 0 || password.Length == 0)
        {
            logger.LogWarning(
                "No owner account exists. Set Bootstrap:OwnerEmail and Bootstrap:OwnerPassword " +
                "(user secrets or environment variables) to create the first one.");
            return;
        }
        if (password.Length < 8 || !password.Any(char.IsLetter) || !password.Any(char.IsDigit))
        {
            logger.LogError("Bootstrap:OwnerPassword must have at least 8 characters with letters and digits.");
            return;
        }
        if (await db.Users.AnyAsync(u => u.Email == email, ct))
        {
            logger.LogError("Cannot create the owner: an account with {Email} already exists.", email);
            return;
        }
        var now = clock.GetUtcNow().UtcDateTime;
        var owner = new User
        {
            FullName = options.OwnerName.Trim(), Email = email, Role = StaffRole.Owner, IsActive = true,
            CreatedAt = now, UpdatedAt = now,
        };
        owner.PasswordHash = hasher.HashPassword(owner, password);
        db.Users.Add(owner);
        await db.SaveChangesAsync(ct);
        db.AuditLogs.Add(new AuditLog
        {
            At = now, ActorName = "System", ActorRole = "Automatic", Action = "staff.create",
            Summary = $"Created the first owner account ({email})", TargetId = owner.Id.ToString(),
        });
        await db.SaveChangesAsync(ct);
        logger.LogInformation("Created the first owner account {Email}", email);
    }
}

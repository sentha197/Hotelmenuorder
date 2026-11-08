using DineQR.Api.Contracts;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace DineQR.Api.Services;

public static class LegalRules
{
    public const int MaxTitle = 120;
    public const int MaxBody = 60_000;
    public const int MaxChangeSummary = 300;

    /// The error a guest order gets while a document still needs accepting.
    public const string RequiredCode = "legalAcceptanceRequired";

    public static string Label(LegalDocumentKind kind) => kind switch
    {
        LegalDocumentKind.Terms => "Terms & Conditions",
        _ => "Privacy Policy",
    };

    /// Fills in `{{restaurant.name}}`, `{{restaurant.address}}`,
    /// `{{restaurant.phone}}` and `{{restaurant.email}}` from the settings,
    /// so the text stays right when those details change.
    public static string Fill(string text, RestaurantSettings settings)
    {
        static string Or(string value, string fallback) =>
            string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
        return text
            .Replace("{{restaurant.name}}", Or(settings.Name, "the restaurant"))
            .Replace("{{restaurant.address}}", Or(settings.Address, "the restaurant's premises"))
            .Replace("{{restaurant.phone}}", Or(settings.Phone, "ask a staff member"))
            .Replace("{{restaurant.email}}", Or(settings.Email, "ask a staff member"));
    }
}

/// Terms & Conditions and the Privacy Policy: versions staff write and
/// publish, and the acceptances guests record before they order.
///
/// A guest has no account, so the customer is the guest session (one per QR
/// scan of a table, kept while the guest rescans the same table). Before a
/// guest's first order in a session they accept the published version of
/// each document; [RequireAcceptedAsync] checks it on every guest order, so
/// no client can skip it. A version published as a material change
/// ([LegalDocument.RequiresReacceptance]) must be accepted again by guests
/// who accepted an earlier one; a minor one only needs accepting by guests
/// who have accepted nothing yet.
public sealed class LegalService(
    AppDbContext db,
    CurrentCaller caller,
    AuditTrail audit,
    Notifier notifier,
    TimeProvider clock)
{
    private DateTime Now => clock.GetUtcNow().UtcDateTime;

    private static LegalDocumentKind ParseKind(string? value) =>
        EnumNames.TryParse<LegalDocumentKind>(value ?? "", out var kind)
            ? kind
            : throw ApiException.Validation("kind", "The document is `terms` or `privacy`.");

    // ------------------------------------------------------------ public

    /// The published documents, placeholders filled in.
    public async Task<List<LegalDocumentDto>> PublishedAsync(CancellationToken ct)
    {
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var documents = await db.LegalDocuments.AsNoTracking()
            .Where(d => d.Status == LegalDocumentStatus.Published)
            .ToListAsync(ct);
        return [.. documents.OrderBy(d => d.Kind).Select(d => ToPublicDto(d, settings))];
    }

    public async Task<LegalDocumentDto> PublishedAsync(string kind, CancellationToken ct)
    {
        var parsed = ParseKind(kind);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);
        var document = await db.LegalDocuments.AsNoTracking()
                           .FirstOrDefaultAsync(d => d.Kind == parsed && d.Status == LegalDocumentStatus.Published, ct)
                       ?? throw ApiException.NotFound($"The restaurant has not published a {LegalRules.Label(parsed)}.");
        return ToPublicDto(document, settings);
    }

    private static LegalDocumentDto ToPublicDto(LegalDocument d, RestaurantSettings settings) =>
        new(EnumNames.ToName(d.Kind), d.Version, LegalRules.Fill(d.Title, settings),
            LegalRules.Fill(d.Body, settings), d.ChangeSummary, d.PublishedAt);

    // ------------------------------------------------------------ guests

    private (Guid Session, int Table) RequireGuest() =>
        caller.IsGuest && caller.GuestSessionId is { } session && caller.GuestTable is { } table
            ? (session, table)
            : throw ApiException.Forbidden("Only a guest session can accept the restaurant's documents.");

    /// What this guest session has accepted and still has to.
    public async Task<GuestLegalStatusDto> GuestStatusAsync(CancellationToken ct)
    {
        var (session, _) = RequireGuest();
        return await StatusAsync(session, ct);
    }

    private async Task<GuestLegalStatusDto> StatusAsync(Guid session, CancellationToken ct)
    {
        var published = await db.LegalDocuments.AsNoTracking()
            .Where(d => d.Status == LegalDocumentStatus.Published)
            .ToListAsync(ct);
        // The latest material change of each kind, up to the published one:
        // an acceptance of that version or a later one still counts.
        var material = await db.LegalDocuments.AsNoTracking()
            .Where(d => d.PublishedAt != null && d.RequiresReacceptance)
            .Select(d => new { d.Kind, d.Version })
            .ToListAsync(ct);
        var accepted = await db.LegalAcceptances.AsNoTracking()
            .Where(a => a.GuestSessionId == session && a.Accepted)
            .GroupBy(a => a.Kind)
            .Select(g => new { Kind = g.Key, Version = g.Max(a => a.Version), At = g.Max(a => a.AcceptedAt) })
            .ToListAsync(ct);
        var settings = await db.Settings.AsNoTracking().SingleAsync(ct);

        var items = new List<GuestLegalItemDto>();
        foreach (var document in published.OrderBy(d => d.Kind))
        {
            var minimum = material
                .Where(m => m.Kind == document.Kind && m.Version <= document.Version)
                .Select(m => m.Version)
                .DefaultIfEmpty(document.Version)
                .Max();
            var mine = accepted.FirstOrDefault(a => a.Kind == document.Kind);
            var required = mine == null || mine.Version < minimum;
            items.Add(new GuestLegalItemDto(
                EnumNames.ToName(document.Kind), document.Version, LegalRules.Fill(document.Title, settings),
                document.ChangeSummary, document.PublishedAt, required, mine?.Version, mine?.At));
        }
        return new GuestLegalStatusDto(items.All(i => !i.Required), items);
    }

    /// Records that the guest accepted the listed versions. Each must be the
    /// version published now: a guest cannot accept text they were not
    /// shown, nor one that has since been replaced (409 `legalVersionChanged`,
    /// so the app reloads it). Accepting again is harmless.
    public async Task<GuestLegalStatusDto> AcceptAsync(LegalAcceptRequest request, CancellationToken ct)
    {
        var (session, table) = RequireGuest();
        var items = request.Documents ?? [];
        if (items.Count is < 1 or > 2)
        {
            throw ApiException.Validation("documents", "List the documents you accept.");
        }
        var kinds = items.Select(i => ParseKind(i.Kind)).ToList();
        if (kinds.Distinct().Count() != kinds.Count)
        {
            throw ApiException.Validation("documents", "Each document can be listed once.");
        }
        var published = await db.LegalDocuments.AsNoTracking()
            .Where(d => d.Status == LegalDocumentStatus.Published && kinds.Contains(d.Kind))
            .ToListAsync(ct);
        var now = Now;
        int? tableNumber = OrderTables.IsTakeaway(table) ? null : table;
        foreach (var (item, kind) in items.Zip(kinds))
        {
            var document = published.FirstOrDefault(d => d.Kind == kind);
            if (document == null || document.Version != item.Version)
            {
                throw ApiException.Conflict("legalVersionChanged",
                    $"The {LegalRules.Label(kind)} has just been updated. Please read the current version.");
            }
            // The table can have been removed since the session started; the
            // record then keeps no table, like the session itself.
            await db.Database.ExecuteSqlInterpolatedAsync($"""
                INSERT INTO legal_acceptances (settings_id, guest_session_id, table_number, document_id, kind,
                                               version, accepted, accepted_at)
                SELECT {document.SettingsId}, {session},
                       (SELECT number FROM restaurant_tables WHERE number = {tableNumber}),
                       {document.Id}, {EnumNames.ToName(kind)}, {document.Version}, TRUE, {now}
                WHERE EXISTS (SELECT 1 FROM guest_sessions WHERE id = {session})
                ON CONFLICT (guest_session_id, document_id) DO NOTHING
                """, ct);
        }
        return await StatusAsync(session, ct);
    }

    /// Before a guest order: every published document accepted (409
    /// `legalAcceptanceRequired` otherwise). Staff orders are not affected.
    public async Task RequireAcceptedAsync(Guid session, CancellationToken ct)
    {
        var status = await StatusAsync(session, ct);
        if (status.CanOrder) return;
        var missing = status.Documents.Where(d => d.Required).Select(d => d.Kind).ToList();
        var names = string.Join(" and ", missing.Select(k => LegalRules.Label(ParseKind(k))));
        throw new ApiException(StatusCodes.Status409Conflict, LegalRules.RequiredCode,
            $"Please accept the {names} before placing your order.",
            new Dictionary<string, string[]> { ["documents"] = [.. missing] });
    }

    // ------------------------------------------------------------ staff

    private async Task<User> RequireViewerAsync(CancellationToken ct)
    {
        var staff = await caller.RequireStaffAsync(ct);
        if (!RolePermissions.Can(staff, Permission.ManageSettings) &&
            !RolePermissions.Can(staff, Permission.ViewAuditLog))
        {
            throw ApiException.Forbidden();
        }
        return staff;
    }

    /// Every version of both documents, newest first, with how many guests
    /// accepted each.
    public async Task<List<LegalDocumentAdminDto>> ListAsync(CancellationToken ct)
    {
        await RequireViewerAsync(ct);
        var documents = await db.LegalDocuments.AsNoTracking()
            .OrderBy(d => d.Kind).ThenByDescending(d => d.Version)
            .ToListAsync(ct);
        var counts = await db.LegalAcceptances.AsNoTracking()
            .GroupBy(a => a.DocumentId)
            .Select(g => new { Id = g.Key, Count = g.Count() })
            .ToDictionaryAsync(g => g.Id, g => g.Count, ct);
        return [.. documents.Select(d => ToAdminDto(d, counts.GetValueOrDefault(d.Id)))];
    }

    private static LegalDocumentAdminDto ToAdminDto(LegalDocument d, int acceptances) =>
        new(d.Id, EnumNames.ToName(d.Kind), d.Version, d.Title, d.Body, d.ChangeSummary,
            d.RequiresReacceptance, EnumNames.ToName(d.Status), d.CreatedAt, d.CreatedByName, d.UpdatedAt,
            d.UpdatedByName, d.PublishedAt, d.PublishedByName, d.RetiredAt, acceptances);

    private static (string Title, string Body, string Summary) Validate(LegalDocumentRequest request)
    {
        var title = (request.Title ?? "").Trim();
        if (title.Length is < 3 or > LegalRules.MaxTitle)
        {
            throw ApiException.Validation("title", $"Give it a title of 3 to {LegalRules.MaxTitle} characters.");
        }
        var body = (request.Body ?? "").Replace("\r\n", "\n").Trim();
        if (body.Length < 50)
        {
            throw ApiException.Validation("body", "Write the document's full text (at least 50 characters).");
        }
        if (body.Length > LegalRules.MaxBody)
        {
            throw ApiException.Validation("body", $"The text can be at most {LegalRules.MaxBody:N0} characters.");
        }
        var summary = (request.ChangeSummary ?? "").Trim();
        if (summary.Length > LegalRules.MaxChangeSummary)
        {
            throw ApiException.Validation("changeSummary",
                $"Describe the changes in at most {LegalRules.MaxChangeSummary} characters.");
        }
        return (title, body, summary);
    }

    /// A new draft version: the next number for its kind.
    public async Task<LegalDocumentAdminDto> CreateAsync(LegalDocumentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var kind = ParseKind(request.Kind);
        var (title, body, summary) = Validate(request);
        var now = Now;
        var latest = await db.LegalDocuments.Where(d => d.Kind == kind)
            .MaxAsync(d => (int?)d.Version, ct) ?? 0;
        var document = new LegalDocument
        {
            SettingsId = RestaurantSettings.SingletonId,
            Kind = kind,
            Version = latest + 1,
            Title = title,
            Body = body,
            ChangeSummary = summary,
            RequiresReacceptance = request.RequiresReacceptance,
            Status = LegalDocumentStatus.Draft,
            CreatedAt = now,
            CreatedByName = staff.FullName,
            UpdatedAt = now,
            UpdatedByName = staff.FullName,
        };
        db.LegalDocuments.Add(document);
        audit.Record(staff, "legal.create",
            $"Drafted {LegalRules.Label(kind)} version {document.Version}", $"{EnumNames.ToName(kind)}:{document.Version}");
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw ApiException.Conflict("conflict", "Someone else created a version at the same time. Try again.");
        }
        return ToAdminDto(document, 0);
    }

    private async Task<LegalDocument> FindAsync(long id, CancellationToken ct) =>
        await db.LegalDocuments.FirstOrDefaultAsync(d => d.Id == id, ct)
        ?? throw ApiException.NotFound("That document version no longer exists.");

    /// Changes a draft. Published and retired versions never change: guests
    /// accepted exactly that text.
    public async Task<LegalDocumentAdminDto> UpdateAsync(long id, LegalDocumentRequest request, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var document = await FindAsync(id, ct);
        if (document.Status != LegalDocumentStatus.Draft)
        {
            throw ApiException.Conflict("legalDocumentLocked",
                "A published version cannot be changed. Create a new version instead.");
        }
        var (title, body, summary) = Validate(request);
        document.Title = title;
        document.Body = body;
        document.ChangeSummary = summary;
        document.RequiresReacceptance = request.RequiresReacceptance;
        document.UpdatedAt = Now;
        document.UpdatedByName = staff.FullName;
        audit.Record(staff, "legal.update",
            $"Edited the draft {LegalRules.Label(document.Kind)} version {document.Version}",
            $"{EnumNames.ToName(document.Kind)}:{document.Version}");
        await db.SaveChangesAsync(ct);
        return ToAdminDto(document, 0);
    }

    /// Deletes a draft that was never published.
    public async Task DeleteDraftAsync(long id, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var document = await FindAsync(id, ct);
        if (document.Status != LegalDocumentStatus.Draft)
        {
            throw ApiException.Conflict("legalDocumentLocked",
                "Only a draft can be deleted. A published version stays on record.");
        }
        db.LegalDocuments.Remove(document);
        audit.Record(staff, "legal.delete",
            $"Deleted the draft {LegalRules.Label(document.Kind)} version {document.Version}",
            $"{EnumNames.ToName(document.Kind)}:{document.Version}");
        await db.SaveChangesAsync(ct);
    }

    /// Publishes a draft: guests see it from now on, and the version it
    /// replaces is retired. The first version of a kind ever published always
    /// needs accepting.
    public async Task<LegalDocumentAdminDto> PublishAsync(long id, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        await using var transaction = await db.Database.BeginTransactionAsync(ct);
        var document = await FindAsync(id, ct);
        if (document.Status != LegalDocumentStatus.Draft)
        {
            throw ApiException.Conflict("legalDocumentLocked", "Only a draft can be published.");
        }
        var newest = await db.LegalDocuments
            .Where(d => d.Kind == document.Kind && d.PublishedAt != null)
            .MaxAsync(d => (int?)d.Version, ct);
        if (newest is { } version && version > document.Version)
        {
            throw ApiException.Conflict("legalVersionOutdated",
                $"Version {version} was published after this draft was written. Create a new version instead.");
        }
        var now = Now;
        var current = await db.LegalDocuments
            .Where(d => d.Kind == document.Kind && d.Status == LegalDocumentStatus.Published)
            .ToListAsync(ct);
        foreach (var old in current)
        {
            old.Status = LegalDocumentStatus.Retired;
            old.RetiredAt = now;
        }
        // Retire first: the database allows one published version per kind.
        await db.SaveChangesAsync(ct);
        if (newest == null) document.RequiresReacceptance = true;
        document.Status = LegalDocumentStatus.Published;
        document.PublishedAt = now;
        document.PublishedByName = staff.FullName;
        document.UpdatedAt = now;
        document.UpdatedByName = staff.FullName;
        audit.Record(staff, "legal.publish",
            $"Published {LegalRules.Label(document.Kind)} version {document.Version}" +
            (document.RequiresReacceptance ? " (guests must accept it again)" : ""),
            $"{EnumNames.ToName(document.Kind)}:{document.Version}");
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException e) when (e.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
        {
            throw ApiException.Conflict("conflict", "Someone else published a version at the same time. Refresh and try again.");
        }
        await transaction.CommitAsync(ct);
        await notifier.SettingsChanged();
        return ToAdminDto(document, await db.LegalAcceptances.CountAsync(a => a.DocumentId == document.Id, ct));
    }

    /// Withdraws the published version. Guests then see no document of this
    /// kind and are not asked to accept one, until another is published.
    public async Task<LegalDocumentAdminDto> UnpublishAsync(long id, CancellationToken ct)
    {
        var staff = await caller.RequireAsync(Permission.ManageSettings, ct);
        var document = await FindAsync(id, ct);
        if (document.Status != LegalDocumentStatus.Published)
        {
            throw ApiException.Conflict("legalDocumentLocked", "Only the published version can be unpublished.");
        }
        var now = Now;
        document.Status = LegalDocumentStatus.Retired;
        document.RetiredAt = now;
        document.UpdatedAt = now;
        document.UpdatedByName = staff.FullName;
        audit.Record(staff, "legal.unpublish",
            $"Unpublished {LegalRules.Label(document.Kind)} version {document.Version}",
            $"{EnumNames.ToName(document.Kind)}:{document.Version}");
        await db.SaveChangesAsync(ct);
        await notifier.SettingsChanged();
        return ToAdminDto(document, await db.LegalAcceptances.CountAsync(a => a.DocumentId == document.Id, ct));
    }

    /// Acceptance history, newest first: by document kind and version, by
    /// guest session (customer), and between two instants.
    public async Task<List<LegalAcceptanceDto>> AcceptancesAsync(string? kind, int? version, Guid? customer,
        DateTime? from, DateTime? to, int limit, CancellationToken ct)
    {
        await RequireViewerAsync(ct);
        var query = db.LegalAcceptances.AsNoTracking().Include(a => a.Document).AsQueryable();
        if (!string.IsNullOrWhiteSpace(kind))
        {
            var parsed = ParseKind(kind);
            query = query.Where(a => a.Kind == parsed);
        }
        if (version is { } v) query = query.Where(a => a.Version == v);
        if (customer is { } c) query = query.Where(a => a.GuestSessionId == c);
        if (from is { } f) query = query.Where(a => a.AcceptedAt >= f);
        if (to is { } t) query = query.Where(a => a.AcceptedAt < t);
        var rows = await query.OrderByDescending(a => a.AcceptedAt).ThenByDescending(a => a.Id)
            .Take(Math.Clamp(limit, 1, 1000))
            .ToListAsync(ct);
        return
        [
            .. rows.Select(a => new LegalAcceptanceDto(a.Id, a.SettingsId, a.GuestSessionId.ToString(),
                a.TableNumber, EnumNames.ToName(a.Kind), a.Version, a.Document.Title, a.Accepted, a.AcceptedAt)),
        ];
    }
}

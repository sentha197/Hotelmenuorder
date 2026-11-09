using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Tests;

/// Terms & Conditions and Privacy Policy: the published versions, the
/// acceptance a guest records before ordering, versioning by staff, and the
/// acceptance history. Every test leaves both documents published.
[Collection(ApiCollection.Name)]
public class LegalDocumentTests(ApiFactory api) : IAsyncLifetime
{
    public Task InitializeAsync() => EnsurePublishedAsync();

    public Task DisposeAsync() => EnsurePublishedAsync();

    private const string Documents = "/api/v1/admin/legal/documents";

    private static object Line(string id, int quantity) => new { itemId = id, quantity };

    private static Task<HttpResponseMessage> OrderAsync(HttpClient guest) =>
        guest.PostJsonAsync("/api/v1/orders", new
        {
            lines = new[] { Line("samosa", 1) },
            idempotencyKey = HttpTestExtensions.Key(),
        });

    private static async Task<GuestLegalStatusDto> StatusAsync(HttpClient guest) =>
        await (await guest.GetAsync("/api/v1/guest/legal")).ReadAsync<GuestLegalStatusDto>();

    private static Task<HttpResponseMessage> AcceptAsync(HttpClient guest, params (string Kind, int Version)[] items) =>
        guest.PostJsonAsync("/api/v1/guest/legal/acceptances", new
        {
            documents = items.Select(i => new { kind = i.Kind, version = i.Version }),
        });

    private async Task<List<LegalDocumentAdminDto>> AllAsync() =>
        await (await (await api.OwnerAsync()).GetAsync(Documents)).ReadAsync<List<LegalDocumentAdminDto>>();

    private async Task<LegalDocumentAdminDto> PublishedAsync(string kind) =>
        (await AllAsync()).Single(d => d.Kind == kind && d.Status == "published");

    /// Drafts and publishes a new version of [kind], as the owner.
    private async Task<LegalDocumentAdminDto> PublishNewAsync(string kind, bool material, string? body = null)
    {
        var owner = await api.OwnerAsync();
        var draft = await (await owner.PostJsonAsync(Documents, new
        {
            kind,
            title = kind == "terms" ? "Terms & Conditions" : "Privacy Policy",
            body = body ?? $"## Updated\n\nThis is an updated {kind} document for {{{{restaurant.name}}}}, with enough text.",
            changeSummary = material ? "Important changes" : "Wording only",
            requiresReacceptance = material,
        })).ReadAsync<LegalDocumentAdminDto>();
        Assert.Equal("draft", draft.Status);
        return await (await owner.PostJsonAsync($"{Documents}/{draft.Id}/publish", new { }))
            .ReadAsync<LegalDocumentAdminDto>();
    }

    /// Both kinds published again (a test may have unpublished one).
    private async Task EnsurePublishedAsync()
    {
        var all = await AllAsync();
        foreach (var kind in new[] { "terms", "privacy" })
        {
            if (!all.Any(d => d.Kind == kind && d.Status == "published"))
            {
                await PublishNewAsync(kind, material: true);
            }
        }
    }

    [Fact]
    public async Task Both_documents_are_published_with_the_restaurant_details_filled_in()
    {
        var documents = await (await api.Anonymous().GetAsync("/api/v1/legal/documents"))
            .ReadAsync<List<LegalDocumentDto>>();
        Assert.Equal(["terms", "privacy"], documents.Select(d => d.Kind));
        var settings = await (await api.Anonymous().GetAsync("/api/v1/settings")).ReadAsync<SettingsDto>();
        Assert.All(documents, d =>
        {
            Assert.DoesNotContain("{{", d.Body);
            Assert.Contains(settings.Name, d.Body);
            Assert.NotNull(d.PublishedAt);
        });
        var privacy = await (await api.Anonymous().GetAsync("/api/v1/legal/documents/privacy"))
            .ReadAsync<LegalDocumentDto>();
        Assert.Equal(documents[1].Version, privacy.Version);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await api.Anonymous().GetAsync("/api/v1/legal/documents/cookies")).StatusCode);
    }

    [Fact]
    public async Task A_new_guest_cannot_order_through_the_api_before_accepting()
    {
        var guest = await api.GuestAsync(table: 4, acceptLegal: false);
        var status = await StatusAsync(guest);
        Assert.False(status.CanOrder);
        Assert.All(status.Documents, d => Assert.True(d.Required));
        Assert.All(status.Documents, d => Assert.Null(d.AcceptedVersion));

        var refused = await OrderAsync(guest);
        Assert.Equal(HttpStatusCode.Conflict, refused.StatusCode);
        Assert.Equal("legalAcceptanceRequired", await refused.ErrorCodeAsync());
        Assert.Contains("Terms & Conditions and Privacy Policy", await refused.Content.ReadAsStringAsync());

        // Staff orders for the table are not affected.
        var waiter = await api.NewStaffAsync("waiter");
        Assert.Equal(HttpStatusCode.Created, (await waiter.PostJsonAsync("/api/v1/admin/orders", new
        {
            lines = new[] { Line("samosa", 1) }, idempotencyKey = HttpTestExtensions.Key(), tableNumber = 4,
        })).StatusCode);
    }

    [Fact]
    public async Task Terms_and_privacy_are_accepted_and_recorded_separately()
    {
        var guest = await api.GuestAsync(table: 6, acceptLegal: false);
        var status = await StatusAsync(guest);
        var terms = status.Documents.Single(d => d.Kind == "terms");
        var privacy = status.Documents.Single(d => d.Kind == "privacy");

        var afterTerms = await (await AcceptAsync(guest, ("terms", terms.Version))).ReadAsync<GuestLegalStatusDto>();
        Assert.False(afterTerms.CanOrder);
        Assert.False(afterTerms.Documents.Single(d => d.Kind == "terms").Required);
        var refused = await OrderAsync(guest);
        Assert.Equal("legalAcceptanceRequired", await refused.ErrorCodeAsync());
        Assert.Contains("Privacy Policy", await refused.Content.ReadAsStringAsync());
        Assert.DoesNotContain("Terms", await refused.Content.ReadAsStringAsync());

        var after = await (await AcceptAsync(guest, ("privacy", privacy.Version))).ReadAsync<GuestLegalStatusDto>();
        Assert.True(after.CanOrder);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);

        // Accepting again records nothing new.
        (await AcceptAsync(guest, ("terms", terms.Version), ("privacy", privacy.Version))).EnsureSuccessStatusCode();
        var owner = await api.OwnerAsync();
        var history = await (await owner.GetAsync("/api/v1/admin/legal/acceptances?limit=1000"))
            .ReadAsync<List<LegalAcceptanceDto>>();
        // Newest first: this guest's two records.
        var mine = history.Where(a => a.TableNumber == 6).Take(2).ToList();
        Assert.Single(mine.Select(a => a.CustomerId).Distinct());
        Assert.Contains(mine, a => a.Kind == "terms" && a.Version == terms.Version && a.Accepted);
        Assert.Contains(mine, a => a.Kind == "privacy" && a.Version == privacy.Version && a.Accepted);
        Assert.All(mine, a => Assert.Equal(1, a.HotelId));
        Assert.True(mine[0].AcceptedAt >= mine[1].AcceptedAt);

        // Filtering by customer returns exactly this session's records.
        var byCustomer = await (await owner.GetAsync(
                $"/api/v1/admin/legal/acceptances?customer={mine[0].CustomerId}"))
            .ReadAsync<List<LegalAcceptanceDto>>();
        Assert.Equal(2, byCustomer.Count);
    }

    [Fact]
    public async Task Only_the_published_version_can_be_accepted()
    {
        var guest = await api.GuestAsync(table: 7, acceptLegal: false);
        var terms = (await StatusAsync(guest)).Documents.Single(d => d.Kind == "terms");

        var stale = await AcceptAsync(guest, ("terms", terms.Version - 1));
        Assert.Equal(HttpStatusCode.Conflict, stale.StatusCode);
        Assert.Equal("legalVersionChanged", await stale.ErrorCodeAsync());
        Assert.Equal("legalVersionChanged", await (await AcceptAsync(guest, ("terms", terms.Version + 5))).ErrorCodeAsync());
        Assert.Equal(HttpStatusCode.BadRequest, (await AcceptAsync(guest, ("cookies", 1))).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await AcceptAsync(guest)).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await AcceptAsync(guest, ("terms", terms.Version), ("terms", terms.Version))).StatusCode);
        Assert.False((await StatusAsync(guest)).CanOrder);

        // Neither anonymous callers nor staff can accept for a guest.
        Assert.Equal(HttpStatusCode.Unauthorized, (await AcceptAsync(api.Anonymous(), ("terms", terms.Version))).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden,
            (await AcceptAsync(await api.OwnerAsync(), ("terms", terms.Version))).StatusCode);
    }

    [Fact]
    public async Task A_returning_guest_keeps_their_acceptance_while_the_session_lasts()
    {
        var first = await api.Anonymous().PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = "DINEQR:TABLE:08" });
        var token = (await first.ReadAsync<GuestSessionResponse>()).GuestToken;
        var guest = api.WithToken(token);
        await ApiFactory.AcceptLegalAsync(guest);

        // Rescanning the same table keeps the session, and so the acceptance.
        var rescan = await guest.PostJsonAsync("/api/v1/guest/sessions", new { qrPayload = "DINEQR:TABLE:08" });
        var again = api.WithToken((await rescan.ReadAsync<GuestSessionResponse>()).GuestToken);
        Assert.True((await StatusAsync(again)).CanOrder);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(again)).StatusCode);

        // Someone else at the same table starts their own session and accepts
        // for themselves.
        var other = await api.GuestAsync(table: 8, acceptLegal: false);
        Assert.False((await StatusAsync(other)).CanOrder);
    }

    [Fact]
    public async Task A_material_change_needs_accepting_again_and_a_minor_one_does_not()
    {
        var guest = await api.GuestAsync(table: 10);
        Assert.True((await StatusAsync(guest)).CanOrder);

        // A minor update: guests who accepted before can keep ordering.
        var minor = await PublishNewAsync("privacy", material: false);
        var status = await StatusAsync(guest);
        Assert.True(status.CanOrder);
        var privacy = status.Documents.Single(d => d.Kind == "privacy");
        Assert.Equal(minor.Version, privacy.Version);
        Assert.True(privacy.AcceptedVersion < minor.Version);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);
        // A new guest accepts the version published now.
        var newcomer = await api.GuestAsync(table: 10, acceptLegal: false);
        Assert.True((await StatusAsync(newcomer)).Documents.Single(d => d.Kind == "privacy").Required);

        // A material change: everyone must accept it before ordering again.
        var material = await PublishNewAsync("terms", material: true);
        status = await StatusAsync(guest);
        Assert.False(status.CanOrder);
        var terms = status.Documents.Single(d => d.Kind == "terms");
        Assert.True(terms.Required);
        Assert.Equal(material.Version, terms.Version);
        Assert.Equal("Important changes", terms.ChangeSummary);
        Assert.Equal("legalAcceptanceRequired", await (await OrderAsync(guest)).ErrorCodeAsync());

        await ApiFactory.AcceptLegalAsync(guest);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);
        var accepted = (await StatusAsync(guest)).Documents.Single(d => d.Kind == "terms");
        Assert.Equal(material.Version, accepted.AcceptedVersion);
    }

    [Fact]
    public async Task Staff_manage_versions_and_published_text_never_changes()
    {
        var owner = await api.OwnerAsync();
        var before = await PublishedAsync("terms");

        var draft = await (await owner.PostJsonAsync(Documents, new
        {
            kind = "terms", title = "Terms & Conditions", body = new string('x', 80), changeSummary = "",
            requiresReacceptance = true,
        })).ReadAsync<LegalDocumentAdminDto>();
        Assert.Equal(before.Version + 1, draft.Version);
        Assert.Equal("draft", draft.Status);
        // Guests still see the published version.
        var guestView = await (await api.Anonymous().GetAsync("/api/v1/legal/documents/terms"))
            .ReadAsync<LegalDocumentDto>();
        Assert.Equal(before.Version, guestView.Version);

        var edited = await (await owner.PutAsJsonAsync($"{Documents}/{draft.Id}", new
        {
            title = "Terms of Service", body = new string('y', 90), changeSummary = "New name",
            requiresReacceptance = false,
        }, Json.Options)).ReadAsync<LegalDocumentAdminDto>();
        Assert.Equal("Terms of Service", edited.Title);
        Assert.False(edited.RequiresReacceptance);

        // Validation.
        Assert.Equal(HttpStatusCode.BadRequest, (await owner.PostJsonAsync(Documents, new
        {
            kind = "terms", title = "T", body = "short", requiresReacceptance = true,
        })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await owner.PostJsonAsync(Documents, new
        {
            kind = "cookies", title = "Cookies", body = new string('z', 80), requiresReacceptance = true,
        })).StatusCode);

        // A published version is locked.
        var locked = await owner.PutAsJsonAsync($"{Documents}/{before.Id}", new
        {
            title = "Changed", body = new string('y', 90), requiresReacceptance = true,
        }, Json.Options);
        Assert.Equal("legalDocumentLocked", await locked.ErrorCodeAsync());
        Assert.Equal("legalDocumentLocked", await (await owner.DeleteAsync($"{Documents}/{before.Id}")).ErrorCodeAsync());

        // Publishing retires the previous version.
        var published = await (await owner.PostJsonAsync($"{Documents}/{draft.Id}/publish", new { }))
            .ReadAsync<LegalDocumentAdminDto>();
        Assert.Equal("published", published.Status);
        var all = await AllAsync();
        var retired = all.Single(d => d.Id == before.Id);
        Assert.Equal("retired", retired.Status);
        Assert.NotNull(retired.RetiredAt);
        Assert.Equal(before.Body, retired.Body);
        Assert.Single(all, d => d.Kind == "terms" && d.Status == "published");

        // A draft written before a newer version was published cannot be
        // published over it.
        var older = await (await owner.PostJsonAsync(Documents, new
        {
            kind = "terms", title = "Older draft", body = new string('o', 80), requiresReacceptance = true,
        })).ReadAsync<LegalDocumentAdminDto>();
        await PublishNewAsync("terms", material: true);
        Assert.Equal("legalVersionOutdated",
            await (await owner.PostJsonAsync($"{Documents}/{older.Id}/publish", new { })).ErrorCodeAsync());
        // Drafts can be deleted.
        Assert.Equal(HttpStatusCode.NoContent, (await owner.DeleteAsync($"{Documents}/{older.Id}")).StatusCode);
        Assert.DoesNotContain(await AllAsync(), d => d.Id == older.Id);
    }

    [Fact]
    public async Task Unpublishing_a_document_stops_asking_for_it()
    {
        var owner = await api.OwnerAsync();
        var privacy = await PublishedAsync("privacy");
        var guest = await api.GuestAsync(table: 11, acceptLegal: false);

        var unpublished = await (await owner.PostJsonAsync($"{Documents}/{privacy.Id}/unpublish", new { }))
            .ReadAsync<LegalDocumentAdminDto>();
        Assert.Equal("retired", unpublished.Status);
        Assert.Equal(HttpStatusCode.NotFound,
            (await api.Anonymous().GetAsync("/api/v1/legal/documents/privacy")).StatusCode);
        var status = await StatusAsync(guest);
        Assert.Equal(["terms"], status.Documents.Select(d => d.Kind));

        // The Terms are still required.
        Assert.Equal("legalAcceptanceRequired", await (await OrderAsync(guest)).ErrorCodeAsync());
        await ApiFactory.AcceptLegalAsync(guest);
        Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);

        // Published again (as a new version): it must be accepted.
        await PublishNewAsync("privacy", material: true);
        Assert.Equal("legalAcceptanceRequired", await (await OrderAsync(guest)).ErrorCodeAsync());
    }

    [Fact]
    public async Task Takeaway_guests_accept_too_and_their_records_have_no_table()
    {
        var owner = await api.OwnerAsync();
        var settings = await (await owner.GetAsync("/api/v1/admin/settings")).ReadAsync<SettingsDto>();
        (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings with { Takeaway = true }, Json.Options))
            .EnsureSuccessStatusCode();
        try
        {
            var session = await (await api.Anonymous().PostJsonAsync("/api/v1/guest/sessions",
                new { qrPayload = "DINEQR:TAKEAWAY" })).ReadAsync<GuestSessionResponse>();
            var guest = api.WithToken(session.GuestToken);
            Assert.Equal("legalAcceptanceRequired", await (await OrderAsync(guest)).ErrorCodeAsync());
            await ApiFactory.AcceptLegalAsync(guest);
            Assert.Equal(HttpStatusCode.Created, (await OrderAsync(guest)).StatusCode);
            var history = await (await owner.GetAsync("/api/v1/admin/legal/acceptances?limit=2"))
                .ReadAsync<List<LegalAcceptanceDto>>();
            Assert.All(history, a => Assert.Null(a.TableNumber));
        }
        finally
        {
            (await owner.PutAsJsonAsync("/api/v1/admin/settings", settings, Json.Options)).EnsureSuccessStatusCode();
        }
    }

    [Fact]
    public async Task Only_permitted_staff_manage_documents_or_see_the_history()
    {
        var waiter = await api.NewStaffAsync("waiter");
        Assert.Equal(HttpStatusCode.Forbidden, (await waiter.GetAsync(Documents)).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await waiter.GetAsync("/api/v1/admin/legal/acceptances")).StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await waiter.PostJsonAsync(Documents, new
        {
            kind = "terms", title = "Terms", body = new string('x', 80), requiresReacceptance = true,
        })).StatusCode);

        // The accountant can read the audit log, so can see the history, but
        // cannot change the documents.
        var accountant = await api.NewStaffAsync("accountant");
        (await accountant.GetAsync(Documents)).EnsureSuccessStatusCode();
        (await accountant.GetAsync("/api/v1/admin/legal/acceptances")).EnsureSuccessStatusCode();
        var terms = await PublishedAsync("terms");
        Assert.Equal(HttpStatusCode.Forbidden,
            (await accountant.PostJsonAsync($"{Documents}/{terms.Id}/unpublish", new { })).StatusCode);

        // Guests cannot reach the admin endpoints at all.
        var guest = await api.GuestAsync();
        Assert.Equal(HttpStatusCode.Forbidden, (await guest.GetAsync(Documents)).StatusCode);
    }
}

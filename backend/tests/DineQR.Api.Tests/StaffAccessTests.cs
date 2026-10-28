using System.Net;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Infrastructure;

namespace DineQR.Api.Tests;

/// The owner can give one person access beyond (or below) their role, and the
/// server applies it on the very next request.
[Collection(ApiCollection.Name)]
public class StaffAccessTests(ApiFactory api)
{
    private const string Password = "StaffPass123";

    private async Task<(StaffDto Staff, HttpClient Client)> NewAsync(string role)
    {
        var owner = await api.OwnerAsync();
        var email = $"{role}-{Guid.NewGuid():N}@test.local";
        var created = await (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = $"Test {role}", email, role, password = Password })).ReadAsync<StaffDto>();
        return (created, await api.StaffAsync(email, Password));
    }

    private static Task<HttpResponseMessage> SetAccessAsync(HttpClient client, string id, params string[]? permissions) =>
        client.PutAsJsonAsync($"/api/v1/admin/staff/{id}/access", new { permissions }, Json.Options);

    private static Task<HttpStatusCode> StatusAsync(HttpClient client, string url) =>
        client.GetAsync(url).ContinueWith(t => t.Result.StatusCode);

    [Fact]
    public async Task An_extra_permission_works_straight_away()
    {
        var owner = await api.OwnerAsync();
        var (kitchen, client) = await NewAsync("kitchen");
        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/audit"));

        var updated = await (await SetAccessAsync(owner, kitchen.Id,
            "viewOrders", "manageKitchen", "viewMenu", "viewAuditLog")).ReadAsync<StaffDto>();

        Assert.True(updated.CustomAccess);
        Assert.Contains("viewAuditLog", updated.Permissions);
        Assert.Equal(HttpStatusCode.OK, await StatusAsync(client, "/api/v1/admin/audit"));

        var listed = (await (await owner.GetAsync("/api/v1/admin/staff")).ReadAsync<List<StaffDto>>())
            .Single(s => s.Id == kitchen.Id);
        Assert.True(listed.CustomAccess);
        Assert.Contains("viewAuditLog", listed.Permissions);
    }

    [Fact]
    public async Task A_permission_left_out_is_taken_away()
    {
        var owner = await api.OwnerAsync();
        var (cashier, client) = await NewAsync("cashier");
        Assert.Equal(HttpStatusCode.OK, await StatusAsync(client, "/api/v1/admin/orders"));

        var updated = await (await SetAccessAsync(owner, cashier.Id, "viewBills", "collectPayments"))
            .ReadAsync<StaffDto>();

        Assert.True(updated.CustomAccess);
        Assert.Equal(["collectPayments", "viewBills"], updated.Permissions.Order());
        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/orders"));
    }

    [Fact]
    public async Task Going_back_to_the_role_defaults_clears_the_custom_access()
    {
        var owner = await api.OwnerAsync();
        var (kitchen, client) = await NewAsync("kitchen");
        await SetAccessAsync(owner, kitchen.Id, "viewOrders", "viewAuditLog");

        var reset = await (await SetAccessAsync(owner, kitchen.Id, null)).ReadAsync<StaffDto>();

        Assert.False(reset.CustomAccess);
        Assert.Equal(["manageKitchen", "viewMenu", "viewOrders"], reset.Permissions.Order());
        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/audit"));

        // Choosing exactly what the role already allows is not "custom" either.
        var same = await (await SetAccessAsync(owner, kitchen.Id,
            "viewOrders", "manageKitchen", "viewMenu")).ReadAsync<StaffDto>();
        Assert.False(same.CustomAccess);
    }

    [Fact]
    public async Task A_new_role_starts_from_that_roles_own_permissions()
    {
        var owner = await api.OwnerAsync();
        var (waiter, _) = await NewAsync("waiter");
        await SetAccessAsync(owner, waiter.Id, "viewOrders", "viewAuditLog");

        var changed = await (await owner.PatchAsJsonAsync($"/api/v1/admin/staff/{waiter.Id}",
            new { role = "cashier" }, Json.Options)).ReadAsync<StaffDto>();

        Assert.False(changed.CustomAccess);
        Assert.DoesNotContain("viewAuditLog", changed.Permissions);
        Assert.Contains("collectPayments", changed.Permissions);
    }

    [Fact]
    public async Task Table_assignment_follows_who_can_serve()
    {
        var owner = await api.OwnerAsync();
        var (waiter, _) = await NewAsync("waiter");
        var (kitchen, _) = await NewAsync("kitchen");

        async Task<List<string>> ServerIds() =>
            (await (await owner.GetAsync("/api/v1/admin/servers")).ReadAsync<List<StaffDto>>())
            .Select(s => s.Id).ToList();

        Assert.Contains(waiter.Id, await ServerIds());
        Assert.DoesNotContain(kitchen.Id, await ServerIds());

        await SetAccessAsync(owner, waiter.Id, "viewOrders");
        await SetAccessAsync(owner, kitchen.Id, "viewOrders", "serveOrders");

        Assert.DoesNotContain(waiter.Id, await ServerIds());
        Assert.Contains(kitchen.Id, await ServerIds());
    }

    [Fact]
    public async Task Owners_keep_full_access_and_nobody_edits_their_own()
    {
        var owner = await api.OwnerAsync();
        var me = (await (await owner.GetAsync("/api/v1/admin/staff")).ReadAsync<List<StaffDto>>())
            .Single(s => s.Email == ApiFactory.OwnerEmail);

        var self = await SetAccessAsync(owner, me.Id, "viewOrders");
        Assert.Equal(HttpStatusCode.BadRequest, self.StatusCode);

        var (secondOwner, _) = await NewAsync("owner");
        var other = await SetAccessAsync(owner, secondOwner.Id, "viewOrders");
        Assert.Equal(HttpStatusCode.BadRequest, other.StatusCode);
    }

    [Fact]
    public async Task Unknown_permissions_are_refused()
    {
        var owner = await api.OwnerAsync();
        var (kitchen, _) = await NewAsync("kitchen");

        var response = await SetAccessAsync(owner, kitchen.Id, "viewOrders", "flyTheMoon");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.False((await (await owner.GetAsync("/api/v1/admin/staff")).ReadAsync<List<StaffDto>>())
            .Single(s => s.Id == kitchen.Id).CustomAccess);
    }

    [Fact]
    public async Task Someone_given_manage_staff_still_cannot_touch_owners_or_change_access()
    {
        var owner = await api.OwnerAsync();
        var (manager, client) = await NewAsync("manager");
        var (waiter, _) = await NewAsync("waiter");
        var ownerId = (await (await owner.GetAsync("/api/v1/admin/staff")).ReadAsync<List<StaffDto>>())
            .Single(s => s.Email == ApiFactory.OwnerEmail).Id;

        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/staff"));
        var granted = await SetAccessAsync(owner, manager.Id, "viewOrders", "manageStaff");
        Assert.Equal(HttpStatusCode.OK, granted.StatusCode);
        Assert.Equal(HttpStatusCode.OK, await StatusAsync(client, "/api/v1/admin/staff"));

        // Not their call: access is the owner's.
        Assert.Equal(HttpStatusCode.Forbidden, (await SetAccessAsync(client, waiter.Id, "viewOrders")).StatusCode);

        // And they cannot take over an owner account or make another owner.
        var takeover = await client.PostJsonAsync($"/api/v1/admin/staff/{ownerId}/password",
            new { password = "Hijacked12345" });
        Assert.Equal(HttpStatusCode.Forbidden, takeover.StatusCode);
        var demote = await client.PatchAsJsonAsync($"/api/v1/admin/staff/{ownerId}",
            new { active = false }, Json.Options);
        Assert.Equal(HttpStatusCode.Forbidden, demote.StatusCode);
        var promote = await client.PatchAsJsonAsync($"/api/v1/admin/staff/{waiter.Id}",
            new { role = "owner" }, Json.Options);
        Assert.Equal(HttpStatusCode.Forbidden, promote.StatusCode);
        var create = await client.PostJsonAsync("/api/v1/admin/staff", new
        {
            name = "Sneaky Owner", email = $"sneaky-{Guid.NewGuid():N}@test.local", role = "owner", password = Password,
        });
        Assert.Equal(HttpStatusCode.Forbidden, create.StatusCode);

        // Ordinary staff changes are still theirs to make.
        var reset = await client.PostJsonAsync($"/api/v1/admin/staff/{waiter.Id}/password",
            new { password = "FreshPass12345" });
        Assert.Equal(HttpStatusCode.NoContent, reset.StatusCode);
    }

    private async Task<(StaffDto Staff, HttpClient Client)> NewCustomAsync(string title)
    {
        var owner = await api.OwnerAsync();
        var email = $"custom-{Guid.NewGuid():N}@test.local";
        var created = await (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = $"Test {title}", email, role = "custom", roleTitle = title, password = Password }))
            .ReadAsync<StaffDto>();
        return (created, await api.StaffAsync(email, Password));
    }

    [Fact]
    public async Task A_role_with_any_name_starts_with_no_access_until_the_owner_grants_it()
    {
        var owner = await api.OwnerAsync();
        var (officer, client) = await NewCustomAsync("  Officer ");

        Assert.Equal("custom", officer.Role);
        Assert.Equal("Officer", officer.RoleTitle);
        Assert.Empty(officer.Permissions);
        Assert.False(officer.CustomAccess);
        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/orders"));

        var granted = await (await SetAccessAsync(owner, officer.Id, "viewOrders", "viewBills"))
            .ReadAsync<StaffDto>();
        Assert.True(granted.CustomAccess);
        Assert.Equal("Officer", granted.RoleTitle);
        Assert.Equal(HttpStatusCode.OK, await StatusAsync(client, "/api/v1/admin/orders"));

        // Granting nothing again is the same as the role's defaults.
        var none = await (await SetAccessAsync(owner, officer.Id)).ReadAsync<StaffDto>();
        Assert.False(none.CustomAccess);
        Assert.Equal(HttpStatusCode.Forbidden, await StatusAsync(client, "/api/v1/admin/orders"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData(" ")]
    [InlineData("A")]
    [InlineData("A name that is much too long to be a role")]
    public async Task A_custom_role_needs_a_readable_name(string? title)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostJsonAsync("/api/v1/admin/staff", new
        {
            name = "Nameless", email = $"nameless-{Guid.NewGuid():N}@test.local",
            role = "custom", roleTitle = title, password = Password,
        });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task A_name_only_belongs_to_custom_roles_and_renaming_keeps_the_access()
    {
        var owner = await api.OwnerAsync();
        var email = $"kitchen-{Guid.NewGuid():N}@test.local";
        var kitchen = await (await owner.PostJsonAsync("/api/v1/admin/staff",
            new { name = "Kitchen Kim", email, role = "kitchen", roleTitle = "Chef", password = Password }))
            .ReadAsync<StaffDto>();
        Assert.Null(kitchen.RoleTitle);

        var (officer, _) = await NewCustomAsync("Officer");
        await SetAccessAsync(owner, officer.Id, "viewOrders");

        Task<HttpResponseMessage> Patch(string id, object body) =>
            owner.PatchAsJsonAsync($"/api/v1/admin/staff/{id}", body, Json.Options);

        var renamed = await (await Patch(officer.Id, new { role = "custom", roleTitle = "Inspector" }))
            .ReadAsync<StaffDto>();
        Assert.Equal("Inspector", renamed.RoleTitle);
        Assert.True(renamed.CustomAccess);
        Assert.Equal(["viewOrders"], renamed.Permissions);

        // A real role replaces the name and starts from its own permissions.
        var cashier = await (await Patch(officer.Id, new { role = "cashier" })).ReadAsync<StaffDto>();
        Assert.Null(cashier.RoleTitle);
        Assert.False(cashier.CustomAccess);
        Assert.Contains("collectPayments", cashier.Permissions);

        // And a custom name needs a name.
        Assert.Equal(HttpStatusCode.BadRequest, (await Patch(kitchen.Id, new { role = "custom" })).StatusCode);
    }

    [Fact]
    public async Task A_change_of_access_is_recorded_in_the_activity_log()
    {
        var owner = await api.OwnerAsync();
        var (kitchen, _) = await NewAsync("kitchen");

        await SetAccessAsync(owner, kitchen.Id, "viewOrders", "manageKitchen", "viewMenu", "viewAuditLog");

        var events = await (await owner.GetAsync("/api/v1/admin/audit?action=staff.access")).ReadAsync<List<AuditDto>>();
        var entry = Assert.Single(events, e => e.Target == kitchen.Id);
        Assert.Contains("custom access", entry.Summary);
    }
}

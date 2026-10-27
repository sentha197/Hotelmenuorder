using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;

namespace DineQR.Api.Endpoints;

/// The HTTP API (`/api/v1`). Handlers only translate HTTP; every rule and
/// permission check lives in the services, so no endpoint can skip one.
public static class ApiEndpoints
{
    public static void MapDineQrApi(this IEndpointRouteBuilder app)
    {
        var api = app.MapGroup("/api/v1");
        MapAuth(api);
        MapPublic(api);
        MapGuestAndShared(api);
        MapAdmin(api.MapGroup("/admin").RequireAuthorization(Policies.Staff).WithTags("Admin"));
    }

    private static void MapAuth(RouteGroupBuilder api)
    {
        var auth = api.MapGroup("/auth").WithTags("Auth");
        auth.MapPost("/login", (LoginRequest request, AuthService service, CancellationToken ct) =>
                service.LoginAsync(request, ct))
            .AllowAnonymous().RequireRateLimiting(RateLimits.Login);
        auth.MapPost("/refresh", (RefreshRequest request, AuthService service, CancellationToken ct) =>
                service.RefreshAsync(request, ct))
            .AllowAnonymous().RequireRateLimiting(RateLimits.Login);
        auth.MapPost("/logout", async (RefreshRequest? request, AuthService service, CurrentCaller caller,
                CancellationToken ct) =>
            {
                var actor = await caller.StaffAsync(ct);
                await service.LogoutAsync(request?.RefreshToken, caller.StaffSessionId, actor, ct);
                return Results.NoContent();
            })
            .AllowAnonymous();
        auth.MapGet("/me", async (CurrentCaller caller, CancellationToken ct) =>
                (await caller.RequireStaffAsync(ct)).ToDto())
            .RequireAuthorization(Policies.Staff);
        auth.MapPost("/password", async (ChangeOwnPasswordRequest request, AuthService service,
                CurrentCaller caller, CancellationToken ct) =>
            {
                await service.ChangeOwnPasswordAsync(await caller.RequireStaffAsync(ct), request, ct);
                return Results.NoContent();
            })
            .RequireAuthorization(Policies.Staff);
    }

    private static void MapPublic(RouteGroupBuilder api)
    {
        var pub = api.MapGroup("").WithTags("Public").AllowAnonymous();
        pub.MapGet("/settings", (SettingsService service, CancellationToken ct) => service.PublicAsync(ct));
        pub.MapGet("/menu", (MenuService service, CancellationToken ct) => service.PublicMenuAsync(ct));
        // Dish photos are on the anonymous customer menu. A photo never
        // changes once stored (a replacement gets a new id), so it can be
        // cached for good.
        pub.MapGet("/images/{file}", async (string file, ImageStorage storage, HttpContext http,
                CancellationToken ct) =>
            {
                var image = await storage.FindAsync(file, ct)
                    ?? throw ApiException.NotFound("That photo no longer exists.");
                http.Response.Headers.CacheControl = "public,max-age=31536000,immutable";
                return Results.File(
                    image.Data, image.ContentType,
                    entityTag: new Microsoft.Net.Http.Headers.EntityTagHeaderValue($"\"{image.Id:n}\""));
            });
        pub.MapGet("/tables/{number:int}", (int number, SettingsService service, CancellationToken ct) =>
            service.PublicTableAsync(number, ct));
        // Table numbers and whether they take orders (no staff details), so
        // the app can check a scanned code before asking for a session.
        pub.MapGet("/tables", (SettingsService service, CancellationToken ct) => service.PublicTablesAsync(ct));
        // Payment mode and which provider handles online payments (no secrets).
        pub.MapGet("/payments/config", (SettingsService service, CancellationToken ct) =>
            service.PaymentConfigAsync(ct));
        // Scanning a table QR starts (or keeps) a table-scoped guest session.
        pub.MapPost("/guest/sessions", (GuestSessionRequest request, AuthService service, CurrentCaller caller,
                CancellationToken ct) =>
                service.StartGuestSessionAsync(request, caller.GuestSessionId, caller.GuestTable, ct))
            .RequireRateLimiting(RateLimits.Guest);
    }

    private static void MapGuestAndShared(RouteGroupBuilder api)
    {
        // Guest session only.
        var guest = api.MapGroup("").RequireAuthorization(Policies.Guest).WithTags("Guest");
        guest.MapPost("/orders", async (PlaceOrderRequest request, OrderService service, CancellationToken ct) =>
            {
                var (order, created) = await service.PlaceAsync(request, ct);
                return created
                    ? Results.Created($"/api/v1/orders/{order.Id}", order.ToDto())
                    : Results.Ok(order.ToDto());
            })
            .RequireRateLimiting(RateLimits.Orders);
        guest.MapGet("/orders", async (OrderService service, CancellationToken ct) =>
            (await service.ForGuestAsync(ct)).Select(o => o.ToDto()));
        guest.MapPost("/orders/{id}/feedback", async (string id, FeedbackRequest request, OrderService service,
                CancellationToken ct) => (await service.SubmitFeedbackAsync(id, request, ct)).ToDto());
        guest.MapGet("/bills", async (BillingService service, CancellationToken ct) =>
            (await service.ForGuestAsync(ct)).Select(i => i.ToDto()));
        // "I will pay at the counter": a notice for staff, not a payment.
        guest.MapPost("/bills/{id}/counter-request", async (string id, CounterRequestBody request,
                BillingService service, CancellationToken ct) =>
            (await service.RequestCounterPaymentAsync(id, request, ct)).ToDto())
            .RequireRateLimiting(RateLimits.Orders);
        guest.MapDelete("/bills/{id}/counter-request", async (string id, BillingService service,
                CancellationToken ct) => (await service.CancelCounterRequestAsync(id, ct)).ToDto())
            .RequireRateLimiting(RateLimits.Orders);

        // A guest for their own records, or staff with the permission.
        var shared = api.MapGroup("").RequireAuthorization().WithTags("Orders and bills");
        shared.MapGet("/orders/{id}", async (string id, OrderService service, CancellationToken ct) =>
            (await service.GetAsync(id, ct)).ToDto());
        shared.MapGet("/orders/{id}/bill", async (string id, BillingService service, CancellationToken ct) =>
            (await service.ForOrderAsync(id, ct)).ToDto());
        shared.MapGet("/bills/{id}", async (string id, BillingService service, CancellationToken ct) =>
            (await service.GetAsync(id, ct)).ToDto());
        shared.MapPost("/payments/intents", async (PaymentIntentRequest request, BillingService service,
                PaymentProviders providers, CancellationToken ct) =>
            {
                var (payment, providerOrderId) = await service.CreateIntentAsync(request, ct);
                var dto = payment.ToDto();
                return new PaymentIntentResponse(dto, payment.Provider, payment.IsSimulated,
                    providerOrderId, providers.Named(payment.Provider)?.PublicKeyId, payment.AmountPaise,
                    payment.Currency, dto.Mode);
            })
            .RequireRateLimiting(RateLimits.Orders);
        shared.MapPost("/payments/{id}/confirm", async (string id, PaymentConfirmRequest request,
                BillingService service, CancellationToken ct) =>
            {
                var (payment, invoice) = await service.ConfirmAsync(id, request, ct);
                return new PaymentResultDto(payment.ToDto(), invoice.ToDto());
            });
        shared.MapGet("/payments/{id}", async (string id, BillingService service, CancellationToken ct) =>
        {
            var (payment, invoice) = await service.RefreshPaymentAsync(id, ct);
            return new PaymentResultDto(payment.ToDto(), invoice.ToDto());
        });
    }

    private static void MapAdmin(RouteGroupBuilder admin)
    {
        // Menu
        admin.MapGet("/menu", (MenuService service, CancellationToken ct) => service.FullMenuAsync(ct));
        admin.MapPut("/menu/items/{id}", async (string id, MenuItemDto dto, MenuService service,
                CancellationToken ct) => (await service.SaveItemAsync(id, dto, ct)).ToDto());
        admin.MapPatch("/menu/items/{id}", async (string id, AvailabilityRequest request, MenuService service,
                CancellationToken ct) => (await service.SetFlagsAsync(id, request, ct)).ToDto());
        admin.MapPut("/menu/categories", async (List<CategoryDto> categories, MenuService service,
                CancellationToken ct) =>
            (await service.SaveCategoriesAsync(categories, ct)).Select(c => c.ToDto()));

        // Dish photos. The upload is a plain bearer-authenticated API call
        // with no cookies, so the automatic antiforgery check does not apply.
        admin.MapPost("/uploads/dish-images", async (IFormFile file, ImageStorage storage,
                CurrentCaller caller, HttpRequest request, CancellationToken ct) =>
            {
                await caller.RequireAsync(Permission.ManageMenu, ct);
                return new UploadedImageDto(await storage.SaveDishImageAsync(file, request, ct));
            })
            .DisableAntiforgery();

        // Settings and tables
        admin.MapGet("/settings", (SettingsService service, CancellationToken ct) => service.ForStaffAsync(ct));
        admin.MapPut("/settings", (SettingsDto dto, SettingsService service, CancellationToken ct) =>
            service.SaveAsync(dto, ct));
        admin.MapGet("/tables", async (SettingsService service, CancellationToken ct) =>
            (await service.TablesAsync(ct)).Select(t => t.ToDto()));
        admin.MapPut("/tables", async (List<TableDto> tables, SettingsService service, CancellationToken ct) =>
            (await service.SaveTablesAsync(tables, ct)).Select(t => t.ToDto()));
        admin.MapGet("/servers", async (StaffService service, CancellationToken ct) =>
            (await service.ServersAsync(ct)).Select(u => u.ToDto()));

        // Orders and kitchen
        admin.MapGet("/orders", async (DateTime? from, DateTime? to, string? status, OrderService service,
                CancellationToken ct) =>
            (await service.ForStaffAsync(from?.ToUniversalTime(), to?.ToUniversalTime(), status, ct))
            .Select(o => o.ToDto()));
        admin.MapGet("/orders/{id}", async (string id, OrderService service, CancellationToken ct) =>
            (await service.GetAsync(id, ct)).ToDto());
        admin.MapPost("/orders", async (PlaceOrderRequest request, OrderService service, CancellationToken ct) =>
        {
            var (order, created) = await service.PlaceAsync(request, ct);
            return created
                ? Results.Created($"/api/v1/admin/orders/{order.Id}", order.ToDto())
                : Results.Ok(order.ToDto());
        });
        admin.MapPost("/orders/{id}/status", async (string id, StatusChangeRequest request, OrderService service,
                CancellationToken ct) => (await service.ChangeStatusAsync(id, request, ct)).ToDto());

        // Bills, payments and refunds
        admin.MapGet("/bills", async (DateTime? from, DateTime? to, BillingService service, CancellationToken ct) =>
            (await service.ForStaffAsync(from?.ToUniversalTime(), to?.ToUniversalTime(), ct))
            .Select(i => i.ToDto()));
        admin.MapGet("/bills/{id}", async (string id, BillingService service, CancellationToken ct) =>
            (await service.GetAsync(id, ct)).ToDto());
        admin.MapPost("/bills/{id}/payments", async (string id, CounterPaymentRequest request,
                BillingService service, CancellationToken ct) =>
            {
                var (payment, invoice) = await service.RecordCounterPaymentAsync(id, request, ct);
                return new PaymentResultDto(payment.ToDto(), invoice.ToDto());
            });
        admin.MapPost("/bills/{id}/reconcile", async (string id, BillingService service, CancellationToken ct) =>
        {
            var (resolved, invoice) = await service.ReconcileAsync(id, ct);
            return new { resolved, invoice = invoice.ToDto() };
        });
        admin.MapPost("/payments/{id}/refunds", async (string id, RefundRequest request, BillingService service,
                CancellationToken ct) =>
            {
                var (refund, invoice) = await service.RefundAsync(id, request, ct);
                return new { refund = refund.ToDto(), invoice = invoice.ToDto() };
            });

        // Staff and activity
        admin.MapGet("/staff", async (StaffService service, CancellationToken ct) =>
            (await service.ListAsync(ct)).Select(u => u.ToDto()));
        admin.MapPost("/staff", async (CreateStaffRequest request, StaffService service, CancellationToken ct) =>
        {
            var user = await service.CreateAsync(request, ct);
            return Results.Created($"/api/v1/admin/staff/{user.Id}", user.ToDto());
        });
        admin.MapPatch("/staff/{id:long}", async (long id, UpdateStaffRequest request, StaffService service,
                CancellationToken ct) => (await service.UpdateAsync(id, request, ct)).ToDto());
        admin.MapPost("/staff/{id:long}/password", async (long id, PasswordRequest request, StaffService service,
                CancellationToken ct) =>
            {
                await service.ResetPasswordAsync(id, request, ct);
                return Results.NoContent();
            });
        admin.MapGet("/audit", async (DateTime? from, DateTime? to, string? action, int? limit,
                StaffService service, CancellationToken ct) =>
            (await service.AuditAsync(from?.ToUniversalTime(), to?.ToUniversalTime(), action, limit ?? 300, ct))
            .Select(a => a.ToDto()));

        // Inventory
        admin.MapGet("/inventory", (InventoryService service, CancellationToken ct) => service.ListAsync(ct));
        admin.MapPost("/inventory", async (InventoryItemRequest request, InventoryService service,
                CancellationToken ct) => (await service.CreateAsync(request, ct)).ToDto());
        admin.MapPut("/inventory/{id}", async (string id, InventoryItemRequest request, InventoryService service,
                CancellationToken ct) => (await service.UpdateAsync(id, request, ct)).ToDto());
        admin.MapPost("/inventory/{id}/adjustments", async (string id, AdjustmentRequest request,
                InventoryService service, CancellationToken ct) =>
            (await service.AdjustAsync(id, request, ct)).ToDto());

        // Reports (restaurant days, inclusive)
        admin.MapGet("/reports/summary", (DateOnly from, DateOnly to, ReportService service,
            CancellationToken ct) => service.SummaryAsync(from, to, ct));
    }
}

public static class RateLimits
{
    public const string Login = "login";
    public const string Guest = "guest";
    public const string Orders = "orders";
}

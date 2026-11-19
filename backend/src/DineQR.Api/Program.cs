using System.Threading.RateLimiting;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Endpoints;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using System.IO.Compression;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.AspNetCore.StaticFiles;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;
var services = builder.Services;

// Fail early if the production JWT signing key is missing or invalid.
var jwt = config.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();
jwt.Key();
services.AddSingleton(jwt);

services.AddSingleton(TimeProvider.System);
services.ConfigureHttpJsonOptions(options => Json.Configure(options.SerializerOptions));
services.AddProblemDetails();
services.AddExceptionHandler<ApiExceptionHandler>();

// PostgreSQL. The connection string comes from user secrets or the
// ConnectionStrings__DefaultConnection environment variable, never from
// source control.
var connectionString = config.GetConnectionString("DefaultConnection");
if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException(
        "ConnectionStrings:DefaultConnection is not set. Use `dotnet user-secrets set " +
        "\"ConnectionStrings:DefaultConnection\" \"...\"` or the ConnectionStrings__DefaultConnection " +
        "environment variable.");
}
services.AddDbContext<AppDbContext>(options => options
    .UseNpgsql(connectionString)
    .UseSnakeCaseNamingConvention());
services.AddHealthChecks().AddDbContextCheck<AppDbContext>("database");

// Authentication: staff JWTs (short-lived, with rotating refresh tokens)
// and table-scoped guest tokens. SignalR passes the token in the query.
services.AddSingleton<TokenService>();
services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
{
    options.MapInboundClaims = false;
    options.TokenValidationParameters = new TokenService(jwt, TimeProvider.System).ValidationParameters();
    options.Events = new JwtBearerEvents
    {
        OnMessageReceived = context =>
        {
            var token = context.Request.Query["access_token"].ToString();
            if (token.Length > 0 && context.HttpContext.Request.Path.StartsWithSegments("/hubs"))
            {
                context.Token = token;
            }
            return Task.CompletedTask;
        },
    };
});
services.AddAuthorization(Policies.Register);
services.AddSingleton<IAuthorizationHandler, StaffRequirementHandler>();
services.AddHttpContextAccessor();
services.AddScoped<CurrentCaller>();
services.AddScoped<IPasswordHasher<User>, PasswordHasher<User>>();

// Business services.
services.AddScoped<AuditTrail>();
services.AddScoped<AuthService>();
services.AddScoped<OrderService>();
services.AddScoped<BillingService>();
services.AddScoped<MenuService>();
services.AddScoped<PromotionService>();
services.AddScoped<LegalService>();
services.AddScoped<GeofenceService>();
// The dine-in Wi-Fi restriction and where callers' addresses come from.
var network = config.GetSection("Network").Get<NetworkOptions>() ?? new NetworkOptions();
services.AddSingleton(network);
services.AddSingleton<HostAddressCache>();
services.AddScoped<NetworkAccessService>();
services.AddScoped<SettingsService>();
services.AddScoped<StaffService>();
services.AddScoped<InventoryService>();
services.AddScoped<ReportService>();
// Uploaded dish photos: converted to WebP and kept in the database.
var imageStorage = config.GetSection("ImageStorage").Get<ImageStorageOptions>() ?? new ImageStorageOptions();
services.AddSingleton(imageStorage);
services.AddSingleton<ImageNormalizer>();
services.AddScoped<ImageStorage>();
services.AddSingleton<Notifier>();
services.AddSignalR().AddJsonProtocol(options => Json.Configure(options.PayloadSerializerOptions));

// No online payments: guests order through DineQR and pay at the
// restaurant's billing counter, where staff record the payment on the bill
// (BillingService). There is no payment gateway, webhook or UPI integration.

// Browsers (Flutter web) need CORS; the mobile apps do not.
var origins = config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    policy.AllowAnyHeader().AllowAnyMethod().AllowCredentials();
    if (builder.Environment.IsDevelopment())
    {
        // Flutter web picks a random localhost port in development.
        policy.SetIsOriginAllowed(origin =>
            Uri.TryCreate(origin, UriKind.Absolute, out var uri) &&
            (uri.IsLoopback || origins.Contains(origin, StringComparer.OrdinalIgnoreCase)));
    }
    else
    {
        policy.WithOrigins(origins);
    }
}));

// Brute-force protection on sign-in, QR sessions and order creation.
services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    static RateLimitPartition<string> PerClient(HttpContext http, int permits) =>
        RateLimitPartition.GetFixedWindowLimiter(
            http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = permits, Window = TimeSpan.FromMinutes(1) });
    var limits = config.GetSection("RateLimits");
    options.AddPolicy(RateLimits.Login, http => PerClient(http, limits.GetValue("LoginPerMinute", 20)));
    options.AddPolicy(RateLimits.Guest, http => PerClient(http, limits.GetValue("GuestPerMinute", 60)));
    options.AddPolicy(RateLimits.Orders, http => PerClient(http, limits.GetValue("OrdersPerMinute", 60)));
});

// Compressed responses: API JSON (orders and bills lists run to hundreds of
// KB) and the web apps' scripts, styles and fonts shrink by 70-90%, which is
// most of the wait on a phone far from the server. Fastest levels: almost
// all the size saving, at a CPU cost too small to matter.
services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.Providers.Add<BrotliCompressionProvider>();
    options.Providers.Add<GzipCompressionProvider>();
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(
    [
        "application/problem+json", "application/manifest+json", "image/svg+xml",
        "font/ttf", "font/otf", "application/x-font-ttf",
    ]);
});
services.Configure<BrotliCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);
services.Configure<GzipCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);

services.AddOpenApi(options => options.AddDocumentTransformer<BearerSecurityTransformer>());
services.Configure<SeedOptions>(config.GetSection("Seed"));
services.Configure<BootstrapOptions>(config.GetSection("Bootstrap"));

var app = builder.Build();

if (network.UsesHeader && network.ClientIpHeader.Trim().Length == 0)
{
    app.Logger.LogWarning(
        "Network:ClientIpSource is Header but Network:ClientIpHeader is empty: no caller's address is known, " +
        "so the dine-in Wi-Fi restriction cannot be switched on.");
}

// Not for responses that carry new tokens (sign-in, refresh, guest
// sessions) or the live-update hub: compressing secrets next to
// request-influenced content is what BREACH-style attacks exploit.
app.UseWhen(
    http => !http.Request.Path.StartsWithSegments("/api/v1/auth")
            && !http.Request.Path.StartsWithSegments("/api/v1/guest/sessions")
            && !http.Request.Path.StartsWithSegments("/hubs"),
    branch => branch.UseResponseCompression());
app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors();
app.UseRateLimiter();

app.Services.GetRequiredService<ImageNormalizer>().LogSupport();

// Photos uploaded before they moved into the database (see
// ImageStorageOptions.Path) are still served, without authentication like the
// rest of the customer menu. New photos come from /api/v1/images/{id}.
{
    var legacyRoot = Path.IsPathRooted(imageStorage.Path)
        ? imageStorage.Path
        : Path.Combine(app.Environment.ContentRootPath, imageStorage.Path);
    Directory.CreateDirectory(legacyRoot);
    var contentTypes = new FileExtensionContentTypeProvider();
    contentTypes.Mappings[".webp"] = "image/webp";
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(legacyRoot),
        RequestPath = imageStorage.RequestPath,
        ContentTypeProvider = contentTypes,
        ServeUnknownFileTypes = false,
        OnPrepareResponse = context =>
            context.Context.Response.Headers.CacheControl = "public,max-age=604800",
    });
}

app.UseAuthentication();
app.UseAuthorization();

if (app.Environment.IsDevelopment() || config.GetValue<bool>("OpenApi:Enabled"))
{
    app.MapOpenApi();
    app.UseSwaggerUI(options =>
    {
        options.SwaggerEndpoint("/openapi/v1.json", "DineQR API v1");
        options.DocumentTitle = "DineQR API";
    });
}

// Reports only Healthy/Unhealthy: no connection details or errors.
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = (http, report) =>
        http.Response.WriteAsJsonAsync(new { status = report.Status.ToString() }),
});
// Keep-alive target for an external pinger (stops Render's free plan from
// sleeping). No database check, so it doesn't keep Neon's compute awake.
app.MapGet("/ping", () => Results.Text("ok"));
app.MapDineQrApi();
app.MapHub<EventsHub>("/hubs/events");

// The customer web app, when the image carries its build (`web/`, see the
// Dockerfile): files as they are, and index.html for every other page path
// (/t/05, /menu, /bills/...) so links and refreshes open the app. Unknown API
// paths stay 404s.
{
    var webRoot = Path.Combine(app.Environment.ContentRootPath, "web");
    if (File.Exists(Path.Combine(webRoot, "index.html")))
    {
        var webFiles = new StaticFileOptions
        {
            FileProvider = new PhysicalFileProvider(webRoot),
            // A precompressed copy keeps the original file's type.
            ContentTypeProvider = new PrecompressedContentTypes(),
            // Hashed bundles never change; index.html must always be fresh.
            OnPrepareResponse = context =>
                context.Context.Response.Headers.CacheControl =
                    context.Context.Request.Path.StartsWithSegments("/assets")
                    || context.Context.Request.Path.StartsWithSegments("/admin/assets")
                        ? "public,max-age=31536000,immutable"
                        : "no-cache",
        };
        // The build writes Brotli and gzip copies of the hashed assets
        // (tools/precompress.mjs): serve those to browsers that accept them,
        // already at maximum compression and with no work per request.
        app.Use((http, next) =>
        {
            var path = http.Request.Path.Value ?? "";
            if (HttpMethods.IsGet(http.Request.Method) &&
                (path.StartsWith("/assets/", StringComparison.Ordinal) ||
                 path.StartsWith("/admin/assets/", StringComparison.Ordinal)))
            {
                var accepted = http.Request.Headers.AcceptEncoding.ToString();
                foreach (var (encoding, suffix) in new[] { ("br", ".br"), ("gzip", ".gz") })
                {
                    if (!accepted.Contains(encoding, StringComparison.OrdinalIgnoreCase) ||
                        !File.Exists(Path.Combine(webRoot, path.TrimStart('/') + suffix)))
                    {
                        continue;
                    }
                    http.Request.Path = path + suffix;
                    http.Response.Headers.ContentEncoding = encoding;
                    http.Response.Headers.Vary = "Accept-Encoding";
                    break;
                }
            }
            return next(http);
        });
        app.UseStaticFiles(webFiles);
        app.MapFallback("/api/{**rest}", () => Results.NotFound());
        app.MapFallback("/hubs/{**rest}", () => Results.NotFound());
        // The staff admin web app (apps/dineqr_admin_web), built with base
        // /admin/ into web/admin: its own index.html for its page paths.
        if (File.Exists(Path.Combine(webRoot, "admin", "index.html")))
        {
            // Routing ignores a trailing slash, so /admin and /admin/ both land
            // here: redirect only the bare one (relative asset paths need it).
            var adminIndex = Path.Combine(webRoot, "admin", "index.html");
            app.MapGet("/admin", (HttpContext http) =>
            {
                if (!http.Request.Path.Value!.EndsWith('/'))
                    return Results.Redirect("/admin/");
                http.Response.Headers.CacheControl = "no-cache";
                return Results.File(adminIndex, "text/html");
            });
            app.MapFallbackToFile("admin/{*path:nonfile}", "admin/index.html", webFiles);
        }
        app.MapFallbackToFile("{*path:nonfile}", "index.html", webFiles);
    }
}

await StartupTasks.RunAsync(app);
app.Run();

/// Exposed for integration tests (WebApplicationFactory).
public partial class Program;

/// Content types for the web apps' files, where a precompressed copy
/// (`app.js.br`, `app.css.gz`) has the type of the file it compresses.
internal sealed class PrecompressedContentTypes : IContentTypeProvider
{
    private readonly FileExtensionContentTypeProvider _types = new();

    public bool TryGetContentType(string subpath, out string contentType)
    {
        if (subpath.EndsWith(".br", StringComparison.Ordinal)) subpath = subpath[..^3];
        else if (subpath.EndsWith(".gz", StringComparison.Ordinal)) subpath = subpath[..^3];
        return _types.TryGetContentType(subpath, out contentType!);
    }
}

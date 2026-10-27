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
services.AddScoped<SettingsService>();
services.AddScoped<PaymentSettingsService>();
services.AddScoped<StaffService>();
services.AddScoped<InventoryService>();
services.AddScoped<ReportService>();
// Uploaded dish photos: written to the API's own disk and served statically.
var imageStorage = config.GetSection("ImageStorage").Get<ImageStorageOptions>() ?? new ImageStorageOptions();
services.AddSingleton(imageStorage);
services.AddSingleton<ImageStorage>();
services.AddSingleton<Notifier>();
services.AddSignalR().AddJsonProtocol(options => Json.Configure(options.PayloadSerializerOptions));

// Payments: no provider by default (online payment unavailable). The
// simulator is refused outside Development.
var payments = config.GetSection("Payments").Get<PaymentOptions>() ?? new PaymentOptions();
if (payments.Provider.Equals("Simulated", StringComparison.OrdinalIgnoreCase))
{
    if (!builder.Environment.IsDevelopment() && !builder.Environment.IsEnvironment("Testing"))
    {
        throw new InvalidOperationException("The payment simulator can only run in Development.");
    }
    services.AddSingleton<IPaymentProvider, SimulatedPaymentProvider>();
}
else
{
    services.AddSingleton<IPaymentProvider, UnavailablePaymentProvider>();
}
// UPI payments to the restaurant's own account are confirmed by a cashier. No
// bank or provider integration ships with the app; registering an
// IUpiPaymentVerifier here is what would make automatic verification
// available.
services.AddSingleton<IUpiPaymentVerifier, UnavailableUpiPaymentVerifier>();

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

// Brute-force protection on sign-in, QR sessions and order/payment creation.
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

services.AddOpenApi(options => options.AddDocumentTransformer<BearerSecurityTransformer>());
services.Configure<SeedOptions>(config.GetSection("Seed"));
services.Configure<BootstrapOptions>(config.GetSection("Bootstrap"));

var app = builder.Build();

app.UseExceptionHandler();
app.UseStatusCodePages();
app.UseCors();
app.UseRateLimiter();

// Dish photos are shown on the anonymous customer menu, so the upload folder
// is served without authentication. Only files this API wrote land there,
// and only the formats ImageStorage accepts are served.
{
    var storage = app.Services.GetRequiredService<ImageStorage>();
    Directory.CreateDirectory(storage.RootPath);
    var contentTypes = new FileExtensionContentTypeProvider();
    contentTypes.Mappings[".webp"] = "image/webp";
    app.UseStaticFiles(new StaticFileOptions
    {
        FileProvider = new PhysicalFileProvider(storage.RootPath),
        RequestPath = storage.RequestPath,
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
app.MapDineQrApi();
app.MapHub<EventsHub>("/hubs/events");

await StartupTasks.RunAsync(app);
app.Run();

/// Exposed for integration tests (WebApplicationFactory).
public partial class Program;

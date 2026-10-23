using DineQR.Api.Data;
using DineQR.Api.Domain;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.OpenApi;
using Npgsql;

namespace DineQR.Api.Infrastructure;

/// Runs once at start-up: optional migration, the one-time catalogue import
/// and the first owner account.
public static class StartupTasks
{
    public static async Task RunAsync(WebApplication app)
    {
        using var scope = app.Services.CreateScope();
        var provider = scope.ServiceProvider;
        var logger = provider.GetRequiredService<ILoggerFactory>().CreateLogger("DineQR.Startup");
        var db = provider.GetRequiredService<AppDbContext>();
        try
        {
            if (app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
            {
                await db.Database.MigrateAsync();
            }
            var pending = (await db.Database.GetPendingMigrationsAsync()).ToList();
            if (pending.Count > 0)
            {
                logger.LogWarning(
                    "The database has {Count} pending migration(s). Run `dotnet ef database update` " +
                    "(see backend/README.md) before using the API.", pending.Count);
                return;
            }
        }
        catch (NpgsqlException error)
        {
            throw new InvalidOperationException(
                "Cannot reach PostgreSQL with ConnectionStrings:DefaultConnection. Check that the server is " +
                "running and the connection string (user secrets) is correct.", error);
        }

        var seed = provider.GetRequiredService<IOptions<SeedOptions>>().Value;
        if (seed.InitialCatalog)
        {
            await CatalogSeeder.RunAsync(db, seed, app.Environment.ContentRootPath, TimeProvider.System, logger);
        }
        await OwnerBootstrapper.RunAsync(db, provider.GetRequiredService<IOptions<BootstrapOptions>>().Value,
            provider.GetRequiredService<IPasswordHasher<User>>(), TimeProvider.System, logger);
    }
}

/// Adds the bearer token scheme to the OpenAPI document, so Swagger UI's
/// "Authorize" button can call staff and guest endpoints.
internal sealed class BearerSecurityTransformer : IOpenApiDocumentTransformer
{
    public Task TransformAsync(OpenApiDocument document, OpenApiDocumentTransformerContext context,
        CancellationToken cancellationToken)
    {
        document.Components ??= new OpenApiComponents();
        document.Components.SecuritySchemes ??= new Dictionary<string, IOpenApiSecurityScheme>();
        document.Components.SecuritySchemes["Bearer"] = new OpenApiSecurityScheme
        {
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT",
            Description = "A staff access token (POST /api/v1/auth/login) or a guest token (POST /api/v1/guest/sessions).",
        };
        document.Security ??= [];
        document.Security.Add(new OpenApiSecurityRequirement
        {
            [new OpenApiSecuritySchemeReference("Bearer", document)] = [],
        });
        return Task.CompletedTask;
    }
}

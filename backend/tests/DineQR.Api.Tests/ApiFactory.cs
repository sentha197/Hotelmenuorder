using System.Collections.Concurrent;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using DineQR.Api.Services;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Npgsql;

namespace DineQR.Api.Tests;

/// Stands in for a bank or payment-provider integration, which does not exist
/// in the app. Off by default (like production); a test switches it on and
/// scripts what the "bank" reports for a payment id, and must switch it off
/// again.
public sealed class TestUpiVerifier : IUpiPaymentVerifier
{
    public string Name => "Test bank";

    public bool IsAvailable { get; set; }

    /// What the bank reports per payment id. Anything not listed is pending.
    public ConcurrentDictionary<string, ProviderOutcome> Outcomes { get; } = new();

    public Task<ProviderOutcome> CheckAsync(Payment payment, CancellationToken ct) =>
        Task.FromResult(Outcomes.TryGetValue(payment.Id, out var outcome)
            ? outcome
            : new ProviderOutcome(PaymentStatus.Pending));

    public void Reset()
    {
        IsAvailable = false;
        Outcomes.Clear();
    }
}

/// Runs the real API against a throwaway PostgreSQL database
/// (`dineqr_tests` by default), created fresh for each test run and dropped
/// afterwards. The `Testing` environment never loads the API's user secrets,
/// so tests cannot reach the real `dineqr` database.
///
/// Connection: `ConnectionStrings:Tests` from this project's user secrets or
/// the `ConnectionStrings__Tests` environment variable. The database name
/// must contain "test".
public sealed class ApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    public const string OwnerEmail = "owner@test.local";
    public const string OwnerPassword = "OwnerPass123";

    private readonly string _connection;

    /// Uploads go to a throwaway folder, never the API's own wwwroot.
    public string UploadRoot { get; } =
        Path.Combine(Path.GetTempPath(), $"dineqr-test-uploads-{Guid.NewGuid():N}");

    /// Small enough that the "too large" case costs nothing to test.
    public const int MaxUploadBytes = 64 * 1024;

    /// The UPI verifier the API runs with (unavailable until a test says so).
    public TestUpiVerifier Verifier { get; } = new();

    public ApiFactory()
    {
        var config = new ConfigurationBuilder()
            .AddUserSecrets<ApiFactory>(optional: true)
            .AddEnvironmentVariables()
            .Build();
        _connection = config.GetConnectionString("Tests")
            ?? throw new InvalidOperationException(
                "Set ConnectionStrings:Tests (user secrets of DineQR.Api.Tests or ConnectionStrings__Tests).");
        var database = new NpgsqlConnectionStringBuilder(_connection).Database ?? "";
        if (!database.Contains("test", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"Refusing to run tests against \"{database}\": the test database name must contain \"test\".");
        }
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        // Program reads its configuration while the builder is created, so
        // the test settings go in as environment variables of this test
        // process (they also outrank appsettings.json).
        var settings = new Dictionary<string, string>
        {
            ["ConnectionStrings__DefaultConnection"] = _connection,
            ["Jwt__SigningKey"] = "test-signing-key-only-for-the-test-database-0123456789",
            ["Database__MigrateOnStartup"] = "true",
            ["Seed__InitialCatalog"] = "true",
            ["Seed__UtcOffsetMinutes"] = "330",
            ["Bootstrap__OwnerEmail"] = OwnerEmail,
            ["Bootstrap__OwnerPassword"] = OwnerPassword,
            ["Bootstrap__OwnerName"] = "Test Owner",
            ["Payments__Provider"] = "Simulated",
            ["RateLimits__LoginPerMinute"] = "10000",
            ["RateLimits__GuestPerMinute"] = "10000",
            ["RateLimits__OrdersPerMinute"] = "10000",
            ["ImageStorage__Path"] = UploadRoot,
            ["ImageStorage__MaxBytes"] = MaxUploadBytes.ToString(),
        };
        foreach (var (key, value) in settings) Environment.SetEnvironmentVariable(key, value);
        builder.UseEnvironment("Testing");
        builder.ConfigureTestServices(services =>
        {
            services.RemoveAll<IUpiPaymentVerifier>();
            services.AddSingleton<IUpiPaymentVerifier>(Verifier);
        });
    }

    public async Task InitializeAsync()
    {
        await RecreateDatabaseAsync(drop: true, create: true);
        _ = Server; // starts the host: migrations, catalogue seed, first owner
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await DisposeAsync();
        NpgsqlConnection.ClearAllPools();
        await RecreateDatabaseAsync(drop: true, create: false);
        try
        {
            if (Directory.Exists(UploadRoot)) Directory.Delete(UploadRoot, recursive: true);
        }
        catch (IOException)
        {
            // A leftover temp folder is harmless; never fail a test run over it.
        }
    }

    private async Task RecreateDatabaseAsync(bool drop, bool create)
    {
        var target = new NpgsqlConnectionStringBuilder(_connection);
        var admin = new NpgsqlConnectionStringBuilder(_connection) { Database = "postgres", Pooling = false };
        await using var connection = new NpgsqlConnection(admin.ConnectionString);
        await connection.OpenAsync();
        var name = target.Database!.Replace("\"", "");
        if (drop)
        {
            await using var dropCommand = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{name}\" WITH (FORCE)", connection);
            await dropCommand.ExecuteNonQueryAsync();
        }
        if (create)
        {
            await using var createCommand = new NpgsqlCommand($"CREATE DATABASE \"{name}\"", connection);
            await createCommand.ExecuteNonQueryAsync();
        }
    }

    // ------------------------------------------------------------ helpers

    public HttpClient Anonymous() => CreateClient();

    public HttpClient WithToken(string token)
    {
        var client = CreateClient();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        return client;
    }

    public async Task<HttpClient> StaffAsync(string email, string password)
    {
        var response = await Anonymous().PostAsJsonAsync("/api/v1/auth/login", new { email, password });
        response.EnsureSuccessStatusCode();
        var auth = await response.Content.ReadFromJsonAsync<AuthResponse>(Json.Options);
        return WithToken(auth!.AccessToken);
    }

    public Task<HttpClient> OwnerAsync() => StaffAsync(OwnerEmail, OwnerPassword);

    /// Creates a staff account (as the owner) and signs it in.
    public async Task<HttpClient> NewStaffAsync(string role)
    {
        var owner = await OwnerAsync();
        var email = $"{role}-{Guid.NewGuid():N}@test.local";
        const string password = "StaffPass123";
        var created = await owner.PostAsJsonAsync("/api/v1/admin/staff",
            new { name = $"Test {role}", email, role, password });
        created.EnsureSuccessStatusCode();
        return await StaffAsync(email, password);
    }

    public async Task<HttpClient> GuestAsync(int table = 5)
    {
        var response = await Anonymous().PostAsJsonAsync("/api/v1/guest/sessions",
            new { qrPayload = $"DINEQR:TABLE:{table:00}" });
        response.EnsureSuccessStatusCode();
        var session = await response.Content.ReadFromJsonAsync<GuestSessionResponse>(Json.Options);
        return WithToken(session!.GuestToken);
    }
}

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFactory>
{
    public const string Name = "api";
}

public static class HttpTestExtensions
{
    public static async Task<T> ReadAsync<T>(this HttpResponseMessage response)
    {
        var body = await response.Content.ReadAsStringAsync();
        Assert.True(response.IsSuccessStatusCode, $"{(int)response.StatusCode}: {body}");
        return JsonSerializer.Deserialize<T>(body, Json.Options)!;
    }

    /// The `code` of a problem response, e.g. `tableUnavailable`.
    public static async Task<string> ErrorCodeAsync(this HttpResponseMessage response)
    {
        var body = await response.Content.ReadAsStringAsync();
        using var json = JsonDocument.Parse(body);
        return json.RootElement.TryGetProperty("code", out var code) ? code.GetString()! : body;
    }

    public static Task<HttpResponseMessage> PostJsonAsync(this HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, Json.Options);

    public static string Key() => Guid.NewGuid().ToString("N");
}

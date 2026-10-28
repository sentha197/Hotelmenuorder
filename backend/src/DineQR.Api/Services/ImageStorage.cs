using System.Data.Common;
using DineQR.Api.Data;
using DineQR.Api.Domain;
using DineQR.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DineQR.Api.Services;

/// Settings for dish photo uploads (`ImageStorage` in configuration).
public sealed class ImageStorageOptions
{
    /// Largest upload accepted. Kept in step with the admin app's own check
    /// so the user is told before a long upload, not after.
    public long MaxBytes { get; set; } = 10 * 1024 * 1024;

    /// The formats an upload may be, comma-separated, by [ImageNormalizer.Known]
    /// name. This is the one list: the apps do not keep their own, and the
    /// server's refusal message is built from it. (A string rather than an
    /// array so an environment variable can replace it whole; .NET merges
    /// arrays by position and could never shorten one.)
    public string AllowedFormats { get; set; } = "jpeg,png,gif,webp,bmp,tiff,ico,avif,heic";

    /// Stored photos are scaled down to fit this many pixels on each side.
    public int MaxDimension { get; set; } = 1600;

    /// WebP quality of the stored photo (1-100).
    public int Quality { get; set; } = 82;

    /// Largest upload, in pixels, that will be decoded (a decompression-bomb
    /// guard: a tiny file can describe an enormous picture). Decoding needs
    /// about 4 bytes per pixel plus working copies, so keep this in step with
    /// [MaxDecodeMemoryMb] and the host's memory.
    public long MaxSourcePixels { get; set; } = 30_000_000;

    /// Memory the image library may use for one decode.
    public int MaxDecodeMemoryMb { get; set; } = 320;

    /// Absolute base for returned URLs (e.g. `https://cdn.example.com`).
    /// Empty means "build it from the incoming request".
    public string PublicBaseUrl { get; set; } = "";

    /// Folder of photos uploaded before photos moved into the database. They
    /// are still served so old links work wherever the files survived (a
    /// hosted API's disk does not survive a redeploy).
    public string Path { get; set; } = "wwwroot/uploads";

    /// URL prefix the legacy folder is served under.
    public string RequestPath { get; set; } = "/uploads";
}

/// A stored photo as served to the apps.
public sealed record StoredImagePayload(Guid Id, string ContentType, byte[] Data);

/// Saves dish photos and the restaurant's UPI QR picture in the database and
/// returns the URL the apps store.
///
/// Images are kept in PostgreSQL rather than on the API's disk because the
/// disk of a hosted API is wiped on every redeploy, which silently turned
/// every uploaded dish photo into a placeholder. Each upload is converted by
/// [ImageNormalizer] to a WebP, so what is stored is always something every
/// app can draw, whatever the user picked.
public sealed class ImageStorage(
    AppDbContext db,
    ImageNormalizer normalizer,
    ImageStorageOptions options,
    TimeProvider clock,
    ILogger<ImageStorage> logger)
{
    /// Where photos are served from, below the API root.
    public const string RoutePrefix = "/api/v1/images";

    /// Validates, converts and stores [file]. Returns the URL to save on the
    /// menu item.
    public Task<string> SaveDishImageAsync(IFormFile? file, HttpRequest request, CancellationToken ct) =>
        SaveAsync(file, StoredImageKind.Dish, "photo", request, ct);

    /// Validates, converts (without loss, so the code still scans) and stores
    /// [file]. Returns the URL to save in the payment settings.
    public Task<string> SaveUpiQrAsync(IFormFile? file, HttpRequest request, CancellationToken ct) =>
        SaveAsync(file, StoredImageKind.UpiQr, "QR image", request, ct);

    /// [url] rewritten to this server's own address when it names a UPI QR
    /// picture stored here, whatever host it was written with; otherwise
    /// null. The payment settings keep only the rewritten value, so a client
    /// can never make guests load a "QR image" from somewhere else.
    public async Task<string?> CanonicalUpiQrUrlAsync(string url, HttpRequest request, CancellationToken ct)
    {
        var id = IdIn(url);
        if (id is null) return null;
        var stored = await db.StoredImages.AnyAsync(i => i.Id == id && i.Kind == StoredImageKind.UpiQr, ct);
        return stored ? Url(request, id.Value) : null;
    }

    /// Deletes a UPI QR picture stored here. Anything else (a dish photo, a
    /// file from before images moved into the database, another host) is
    /// left alone. A leftover is harmless, so this never fails the caller.
    public async Task TryDeleteUpiQrAsync(string url, CancellationToken ct)
    {
        var id = IdIn(url);
        if (id is null) return;
        try
        {
            await db.StoredImages.Where(i => i.Id == id && i.Kind == StoredImageKind.UpiQr)
                .ExecuteDeleteAsync(ct);
        }
        catch (DbException error)
        {
            logger.LogWarning(error, "Could not delete the replaced UPI QR image {Id}", id);
        }
    }

    private async Task<string> SaveAsync(
        IFormFile? file,
        StoredImageKind kind,
        string noun,
        HttpRequest request,
        CancellationToken ct)
    {
        if (file is null || file.Length == 0)
        {
            throw ApiException.BadRequest("noFile", $"Choose a {noun} to upload.");
        }
        if (file.Length > options.MaxBytes)
        {
            var limit = options.MaxBytes / (1024 * 1024);
            throw ApiException.BadRequest(
                "fileTooLarge", $"That {noun} is too large. The limit is {limit} MB.");
        }

        var bytes = new byte[file.Length];
        await using (var source = file.OpenReadStream())
        {
            await source.ReadExactlyAsync(bytes, ct);
        }

        var image = await normalizer.NormalizeAsync(bytes, ct, lossless: kind == StoredImageKind.UpiQr);
        var id = Guid.NewGuid();
        db.StoredImages.Add(new StoredImage
        {
            Id = id,
            Kind = kind,
            ContentType = image.ContentType,
            SourceContentType = image.Source.ContentType,
            Width = image.Width,
            Height = image.Height,
            Data = image.Data,
            CreatedAt = clock.GetUtcNow().UtcDateTime,
        });
        await db.SaveChangesAsync(ct);
        return Url(request, id);
    }

    /// The photo named by the last segment of its URL (`{id}` or `{id}.webp`).
    public async Task<StoredImagePayload?> FindAsync(string file, CancellationToken ct)
    {
        var name = file.EndsWith(".webp", StringComparison.OrdinalIgnoreCase) ? file[..^5] : file;
        if (!Guid.TryParseExact(name, "N", out var id)) return null;
        return await db.StoredImages.AsNoTracking()
            .Where(i => i.Id == id)
            .Select(i => new StoredImagePayload(i.Id, i.ContentType, i.Data))
            .FirstOrDefaultAsync(ct);
    }

    /// The id in a URL this storage returned (`.../api/v1/images/{id}.webp`,
    /// on any host), or null.
    private static Guid? IdIn(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        var path = Uri.TryCreate(url, UriKind.Absolute, out var absolute) ? absolute.AbsolutePath : url;
        const string prefix = RoutePrefix + "/";
        if (!path.StartsWith(prefix, StringComparison.Ordinal) ||
            !path.EndsWith(".webp", StringComparison.Ordinal))
        {
            return null;
        }
        return Guid.TryParseExact(path[prefix.Length..^".webp".Length], "N", out var id) ? id : null;
    }

    /// Absolute URL for a stored photo. The apps run on phones, so a relative
    /// URL would not resolve; the host the request arrived on is used unless
    /// a public base URL is configured.
    private string Url(HttpRequest request, Guid id)
    {
        var path = $"{RoutePrefix}/{id:n}.webp";
        var configured = options.PublicBaseUrl.Trim();
        return configured.Length > 0
            ? $"{configured.TrimEnd('/')}{path}"
            : $"{request.Scheme}://{request.Host}{path}";
    }
}

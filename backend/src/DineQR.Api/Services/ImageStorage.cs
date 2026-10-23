using DineQR.Api.Infrastructure;

namespace DineQR.Api.Services;

/// Where uploaded dish photos are written and the URL they are served under.
/// Files land on the API's own disk; put [PublicBaseUrl] behind a CDN or
/// reverse proxy if something else serves them in production.
public sealed class ImageStorageOptions
{
    /// Folder on disk. Relative paths resolve against the content root.
    public string Path { get; set; } = "wwwroot/uploads";

    /// URL prefix the folder is served under.
    public string RequestPath { get; set; } = "/uploads";

    /// Largest accepted upload. Kept in step with the admin app's own check
    /// so the user is told before a long upload, not after.
    public long MaxBytes { get; set; } = 5 * 1024 * 1024;

    /// Absolute base for returned URLs (e.g. `https://cdn.example.com`).
    /// Empty means "build it from the incoming request".
    public string PublicBaseUrl { get; set; } = "";
}

/// Saves dish photos and returns the URL the apps should store.
///
/// The declared content type is not trusted: the file's leading bytes decide
/// what it is, so a renamed executable cannot be stored as a `.jpg`.
public sealed class ImageStorage(
    ImageStorageOptions options,
    IWebHostEnvironment environment,
    ILogger<ImageStorage> logger)
{
    /// Subfolder for menu photos, below [ImageStorageOptions.Path].
    private const string DishFolder = "dishes";

    private readonly record struct ImageKind(string Extension, string ContentType);

    private static readonly ImageKind Jpeg = new(".jpg", "image/jpeg");
    private static readonly ImageKind Png = new(".png", "image/png");
    private static readonly ImageKind Webp = new(".webp", "image/webp");

    /// Formats every target platform can decode. Keep in step with the
    /// message in [Sniff] and with the admin app's picker.
    public static readonly string[] AcceptedContentTypes =
        [Jpeg.ContentType, Png.ContentType, Webp.ContentType];

    /// Absolute path of the upload folder.
    public string RootPath => System.IO.Path.IsPathRooted(options.Path)
        ? options.Path
        : System.IO.Path.Combine(environment.ContentRootPath, options.Path);

    public string RequestPath => options.RequestPath;

    /// Validates [file] and writes it under the dish folder.
    /// Returns the URL to store on the menu item.
    public async Task<string> SaveDishImageAsync(
        IFormFile? file,
        HttpRequest request,
        CancellationToken ct)
    {
        if (file is null || file.Length == 0)
        {
            throw ApiException.BadRequest("noFile", "Choose a photo to upload.");
        }
        if (file.Length > options.MaxBytes)
        {
            var limit = options.MaxBytes / (1024 * 1024);
            throw ApiException.BadRequest(
                "fileTooLarge", $"That photo is too large. The limit is {limit} MB.");
        }

        await using var source = file.OpenReadStream();
        // Enough for the longest signature checked (WebP needs 12 bytes).
        var header = new byte[12];
        var read = await source.ReadAtLeastAsync(header, header.Length, throwOnEndOfStream: false, ct);
        var kind = Sniff(header.AsSpan(0, read))
            ?? throw ApiException.BadRequest(
                "unsupportedImageType",
                "That file is not a JPEG, PNG or WebP image.");

        var folder = System.IO.Path.Combine(RootPath, DishFolder);
        Directory.CreateDirectory(folder);
        // The client never names the file: a generated name cannot escape the
        // folder or overwrite an existing photo.
        var name = $"{Guid.NewGuid():n}{kind.Extension}";
        var fullPath = System.IO.Path.Combine(folder, name);

        try
        {
            await using var target = File.Create(fullPath);
            await target.WriteAsync(header.AsMemory(0, read), ct);
            await source.CopyToAsync(target, ct);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            logger.LogError(error, "Could not write an uploaded photo to {Folder}", folder);
            throw ApiException.Unavailable(
                "storageUnavailable", "The photo could not be saved. Please try again.");
        }

        return Url(request, $"{DishFolder}/{name}");
    }

    /// Deletes a photo this storage wrote. Unknown or foreign URLs are
    /// ignored, so a menu item pointing at a bundled asset or a CDN is safe
    /// to "delete". Returns whether a file was removed.
    public bool TryDeleteDishImage(string url)
    {
        var name = DishFileName(url);
        if (name is null) return false;
        var fullPath = System.IO.Path.Combine(RootPath, DishFolder, name);
        try
        {
            if (!File.Exists(fullPath)) return false;
            File.Delete(fullPath);
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // A leftover file is harmless; never fail the request over it.
            logger.LogWarning(error, "Could not delete the photo {Name}", name);
            return false;
        }
    }

    /// The bare file name if [url] points at a dish photo in this store.
    private string? DishFileName(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        var path = Uri.TryCreate(url, UriKind.Absolute, out var absolute)
            ? absolute.AbsolutePath
            : url;
        var prefix = $"{options.RequestPath.TrimEnd('/')}/{DishFolder}/";
        if (!path.StartsWith(prefix, StringComparison.Ordinal)) return null;
        var name = path[prefix.Length..];
        // Must be exactly the generated shape: no separators, no traversal.
        return name.Length is > 0 and <= 64 &&
               name == System.IO.Path.GetFileName(name) &&
               name.All(c => char.IsAsciiLetterOrDigit(c) || c == '.')
            ? name
            : null;
    }

    /// Absolute URL for a file stored at [relativePath]. The apps run on
    /// phones, so a relative URL would not resolve; the host the request
    /// arrived on is used unless a public base URL is configured.
    private string Url(HttpRequest request, string relativePath)
    {
        var path = $"{options.RequestPath.TrimEnd('/')}/{relativePath}";
        var configured = options.PublicBaseUrl.Trim();
        return configured.Length > 0
            ? $"{configured.TrimEnd('/')}{path}"
            : $"{request.Scheme}://{request.Host}{path}";
    }

    private static ImageKind? Sniff(ReadOnlySpan<byte> header) => header switch
    {
        [0xFF, 0xD8, 0xFF, ..] => Jpeg,
        [0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A, ..] => Png,
        [(byte)'R', (byte)'I', (byte)'F', (byte)'F', _, _, _, _,
         (byte)'W', (byte)'E', (byte)'B', (byte)'P'] => Webp,
        _ => null,
    };
}

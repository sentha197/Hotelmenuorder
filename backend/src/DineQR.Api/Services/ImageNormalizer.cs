using DineQR.Api.Infrastructure;
using ImageMagick;
using ImageMagick.Formats;

namespace DineQR.Api.Services;

/// One image format the API knows how to recognise and decode.
public sealed record ImageFormat(string Name, string Label, MagickFormat Decoder, string ContentType);

/// The result of [ImageNormalizer.NormalizeAsync]: the photo re-encoded as
/// something every app can draw, plus what was uploaded.
public sealed record NormalizedImage(
    byte[] Data, string ContentType, int Width, int Height, ImageFormat Source);

/// Turns whatever image a user uploads into one small, upright, metadata-free
/// WebP.
///
/// Three rules keep it safe:
/// * The format is decided by the file's leading bytes, never by its name or
///   declared type, and only formats in [ImageStorageOptions.AllowedFormats]
///   get through.
/// * The bytes are then fully decoded with that format named explicitly, so a
///   file that merely starts like a photo is refused, and ImageMagick never
///   guesses a format (it can otherwise be talked into SVG, PDF or text
///   "delegates").
/// * Size, pixel and memory limits bound what a hostile upload can cost.
public sealed class ImageNormalizer
{
    /// Every format the code can recognise. [ImageStorageOptions.AllowedFormats]
    /// picks which of them an install accepts.
    public static readonly ImageFormat[] Known =
    [
        new("jpeg", "JPEG", MagickFormat.Jpeg, "image/jpeg"),
        new("png", "PNG", MagickFormat.Png, "image/png"),
        new("gif", "GIF", MagickFormat.Gif, "image/gif"),
        new("webp", "WebP", MagickFormat.WebP, "image/webp"),
        new("bmp", "BMP", MagickFormat.Bmp, "image/bmp"),
        new("tiff", "TIFF", MagickFormat.Tiff, "image/tiff"),
        new("ico", "ICO", MagickFormat.Ico, "image/x-icon"),
        new("avif", "AVIF", MagickFormat.Avif, "image/avif"),
        new("heic", "HEIC/HEIF", MagickFormat.Heic, "image/heic"),
    ];

    public const string OutputContentType = "image/webp";

    private static readonly SemaphoreSlim Gate = new(2);

    private readonly ImageStorageOptions _options;
    private readonly ILogger<ImageNormalizer> _logger;
    private readonly Lazy<HashSet<string>> _readable;

    public ImageNormalizer(ImageStorageOptions options, ILogger<ImageNormalizer> logger)
    {
        _options = options;
        _logger = logger;
        // Bounds for one decode. A photo is a few megapixels; these only
        // matter for a hostile or accidental giant.
        ResourceLimits.Memory = (ulong)Math.Max(64, options.MaxDecodeMemoryMb) * 1024 * 1024;
        ResourceLimits.Disk = 256UL * 1024 * 1024;
        ResourceLimits.Width = 20_000;
        ResourceLimits.Height = 20_000;
        ResourceLimits.Thread = 2;
        _readable = new Lazy<HashSet<string>>(() =>
        {
            var readable = MagickNET.SupportedFormats
                .Where(f => f.SupportsReading)
                .Select(f => f.Format)
                .ToHashSet();
            return Allowed.Where(f => readable.Contains(f.Decoder)).Select(f => f.Name).ToHashSet();
        });
    }

    /// The formats this install accepts. Names that are not in [Known] are
    /// ignored.
    public IReadOnlyList<ImageFormat> Allowed => _allowed ??= Known
        .Where(f => _options.AllowedFormats
            .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Contains(f.Name, StringComparer.OrdinalIgnoreCase))
        .ToList();

    private IReadOnlyList<ImageFormat>? _allowed;

    /// Accepted formats the image library on this machine can really read.
    /// Differs from [Allowed] only if a codec is missing from the host.
    public IReadOnlyList<ImageFormat> Readable => Allowed.Where(f => _readable.Value.Contains(f.Name)).ToList();

    /// "JPEG, PNG and WebP" style list for messages.
    public string AllowedLabel
    {
        get
        {
            var names = Allowed.Select(f => f.Label).ToList();
            return names.Count switch
            {
                0 => "no formats",
                1 => names[0],
                _ => $"{string.Join(", ", names[..^1])} and {names[^1]}",
            };
        }
    }

    public void LogSupport()
    {
        var missing = Allowed.Where(f => !_readable.Value.Contains(f.Name)).Select(f => f.Label).ToList();
        _logger.LogInformation("Photo uploads accept: {Formats}", AllowedLabel);
        if (missing.Count > 0)
        {
            _logger.LogWarning(
                "This host's image library cannot read {Formats}; uploads of those will be refused.",
                string.Join(", ", missing));
        }
    }

    /// [lossless] keeps every pixel (for a QR code, which lossy compression
    /// can blur until it no longer scans) at the cost of a larger file.
    public async Task<NormalizedImage> NormalizeAsync(byte[] bytes, CancellationToken ct, bool lossless = false)
    {
        var source = Sniff(bytes);
        if (source is null || !Allowed.Contains(source))
        {
            throw ApiException.BadRequest(
                "unsupportedImageType", $"That file is not a supported image. Use {AllowedLabel}.");
        }
        if (!_readable.Value.Contains(source.Name))
        {
            throw new ApiException(
                StatusCodes.Status415UnsupportedMediaType, "imageFormatUnavailable",
                $"This server cannot read {source.Label} photos. Use another format, such as JPEG or PNG.");
        }

        // Decoding is CPU- and memory-heavy; a couple at a time keeps a small
        // host responsive however many uploads arrive together.
        await Gate.WaitAsync(ct);
        try
        {
            return await Task.Run(() => Convert(bytes, source, lossless), ct);
        }
        finally
        {
            Gate.Release();
        }
    }

    private NormalizedImage Convert(byte[] bytes, ImageFormat source, bool lossless)
    {
        try
        {
            var settings = new MagickReadSettings { Format = source.Decoder, FrameIndex = 0, FrameCount = 1 };

            var info = new MagickImageInfo(bytes, settings);
            if ((long)info.Width * info.Height > _options.MaxSourcePixels)
            {
                throw ApiException.BadRequest(
                    "imageTooLarge",
                    $"That photo is too large ({info.Width}×{info.Height}). Use one under " +
                    $"{_options.MaxSourcePixels / 1_000_000} megapixels.");
            }

            using var image = new MagickImage(bytes, settings);
            // Phones store sideways pixels plus an orientation tag.
            image.AutoOrient();
            ToSrgb(image);
            // Location, device and other metadata never need to leave the server.
            image.Strip();

            var max = (uint)Math.Max(64, _options.MaxDimension);
            if (image.Width > max || image.Height > max)
            {
                image.Resize(new MagickGeometry(max, max));
            }

            image.Format = MagickFormat.WebP;
            image.Quality = (uint)Math.Clamp(_options.Quality, 1, 100);
            if (lossless) image.Settings.SetDefines(new WebPWriteDefines { Lossless = true });
            var data = image.ToByteArray();
            return new NormalizedImage(data, OutputContentType, (int)image.Width, (int)image.Height, source);
        }
        catch (ApiException)
        {
            throw;
        }
        catch (MagickResourceLimitErrorException error)
        {
            _logger.LogWarning(error, "A {Format} upload hit an image resource limit", source.Label);
            throw ApiException.BadRequest("imageTooLarge", "That photo is too large to process. Use a smaller one.");
        }
        catch (MagickMissingDelegateErrorException error)
        {
            _logger.LogError(error, "The image library has no decoder for {Format}", source.Label);
            throw new ApiException(
                StatusCodes.Status415UnsupportedMediaType, "imageFormatUnavailable",
                $"This server cannot read {source.Label} photos. Use another format, such as JPEG or PNG.");
        }
        catch (MagickException error)
        {
            _logger.LogInformation(error, "A {Format} upload could not be decoded", source.Label);
            throw ApiException.BadRequest(
                "invalidImage", $"That {source.Label} file could not be read as a photo. It may be damaged.");
        }
    }

    /// Wide-gamut photos (Display P3 from iPhones, Adobe RGB) are converted to
    /// sRGB before their colour profile is dropped, so colours do not wash out.
    private static void ToSrgb(MagickImage image)
    {
        try
        {
            if (image.GetColorProfile() is { } profile)
            {
                image.TransformColorSpace(profile, ColorProfiles.SRGB);
            }
        }
        catch (MagickException)
        {
            // A broken profile is not worth refusing the photo over.
        }
    }

    /// The format [bytes] start like, or null. Only leading bytes are looked
    /// at here; [Convert] then has to decode the whole file.
    public static ImageFormat? Sniff(ReadOnlySpan<byte> b)
    {
        string? name = b switch
        {
            [0xFF, 0xD8, 0xFF, ..] => "jpeg",
            [0x89, (byte)'P', (byte)'N', (byte)'G', 0x0D, 0x0A, 0x1A, 0x0A, ..] => "png",
            [(byte)'G', (byte)'I', (byte)'F', (byte)'8', (byte)'7' or (byte)'9', (byte)'a', ..] => "gif",
            [(byte)'R', (byte)'I', (byte)'F', (byte)'F', _, _, _, _, (byte)'W', (byte)'E', (byte)'B', (byte)'P', ..] => "webp",
            [(byte)'B', (byte)'M', ..] when IsBmp(b) => "bmp",
            [(byte)'I', (byte)'I', 0x2A, 0x00, ..] or [(byte)'M', (byte)'M', 0x00, 0x2A, ..] => "tiff",
            [0x00, 0x00, 0x01, 0x00, var count, ..] when count > 0 => "ico",
            _ => IsoBaseMediaFormat(b),
        };
        return name is null ? null : Known.First(f => f.Name == name);
    }

    /// BMP's two-byte signature is weak, so the DIB header size is checked too.
    private static bool IsBmp(ReadOnlySpan<byte> b)
    {
        if (b.Length < 18) return false;
        var headerSize = BitConverter.ToUInt32(b.Slice(14, 4));
        return headerSize is 12 or 40 or 52 or 56 or 64 or 108 or 124;
    }

    /// AVIF and HEIC/HEIF share the ISO base media container: a `ftyp` box
    /// listing brands tells them apart.
    private static string? IsoBaseMediaFormat(ReadOnlySpan<byte> b)
    {
        if (b.Length < 16 || !b.Slice(4, 4).SequenceEqual("ftyp"u8)) return null;
        var size = (int)Math.Min(System.Buffers.Binary.BinaryPrimitives.ReadUInt32BigEndian(b), (uint)Math.Min(b.Length, 128));
        var brands = new List<string> { System.Text.Encoding.ASCII.GetString(b.Slice(8, 4)) };
        for (var offset = 16; offset + 4 <= size; offset += 4)
        {
            brands.Add(System.Text.Encoding.ASCII.GetString(b.Slice(offset, 4)));
        }
        if (brands.Any(x => x is "avif" or "avis")) return "avif";
        if (brands.Any(x => x is "heic" or "heix" or "hevc" or "hevx" or "heim" or "heis" or "hevm" or "hevs"
                or "mif1" or "msf1")) return "heic";
        return null;
    }
}

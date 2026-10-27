using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DineQR.Api.Contracts;
using DineQR.Api.Services;
using ImageMagick;

namespace DineQR.Api.Tests;

[Collection(ApiCollection.Name)]
public class ImageUploadTests(ApiFactory api)
{
    private const string Url = "/api/v1/admin/uploads/dish-images";

    /// An orange field with a navy block in the middle. Flat areas keep every
    /// format well under the test upload limit, and the two colours let a test
    /// prove the picture itself (not a placeholder) came back.
    private static MagickImage Sample(uint width = 240, uint height = 180)
    {
        var image = new MagickImage(MagickColors.OrangeRed, width, height);
        using var block = new MagickImage(MagickColors.Navy, width / 3, height / 3);
        image.Composite(block, (int)(width / 3), (int)(height / 3), CompositeOperator.Over);
        return image;
    }

    private static byte[] Encode(string format, MagickImage? image = null)
    {
        var decoder = ImageNormalizer.Known.Single(f => f.Name == format).Decoder;
        using var sample = image is null ? Sample() : null;
        return (image ?? sample!).ToByteArray(decoder);
    }

    /// A buffer that starts with [signature], padded to [length].
    private static byte[] Padded(byte[] signature, int length = 256)
    {
        var bytes = new byte[length];
        signature.CopyTo(bytes, 0);
        return bytes;
    }

    private static readonly byte[] Png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0];

    /// Posts [bytes] as the `file` field of a multipart form. The name and
    /// declared type are deliberately unhelpful by default: neither may be
    /// trusted.
    private static MultipartFormDataContent Form(
        byte[] bytes, string name = "photo.dat", string contentType = "application/octet-stream")
    {
        var content = new ByteArrayContent(bytes);
        content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        return new MultipartFormDataContent { { content, "file", name } };
    }

    private async Task<string> UploadAsync(byte[] bytes, string name = "photo.dat")
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(bytes, name));
        return (await response.ReadAsync<UploadedImageDto>()).Url;
    }

    /// Every format except HEIC, which this machine's library can read but
    /// not write (see Heic_photos_are_decoded below).
    public static TheoryData<string> WritableFormats() =>
        [.. ImageNormalizer.Known.Where(f => f.Name != "heic").Select(f => f.Name)];

    /// Lossy formats shift colours slightly, so "near" is enough to show the
    /// picture itself came back.
    private static bool Near(IMagickColor<byte>? colour, IMagickColor<byte> expected, int tolerance = 48) =>
        colour is not null &&
        Math.Abs(colour.R - expected.R) <= tolerance &&
        Math.Abs(colour.G - expected.G) <= tolerance &&
        Math.Abs(colour.B - expected.B) <= tolerance;

    // --------------------------------------------------------------- formats

    [Theory]
    [MemberData(nameof(WritableFormats))]
    public async Task A_photo_in_any_supported_format_is_converted_stored_and_served_as_webp(string format)
    {
        var url = await UploadAsync(Encode(format));

        Assert.StartsWith("http", url);
        Assert.Contains("/api/v1/images/", url);
        Assert.EndsWith(".webp", url);

        // Reachable without a token: the customer menu is anonymous.
        var served = await api.Anonymous().GetAsync(new Uri(url).AbsolutePath);
        Assert.Equal(HttpStatusCode.OK, served.StatusCode);
        Assert.Equal("image/webp", served.Content.Headers.ContentType?.MediaType);
        Assert.Contains("immutable", served.Headers.CacheControl?.ToString());

        // What came back is the same picture, now a real WebP.
        using var decoded = new MagickImage(
            await served.Content.ReadAsByteArrayAsync(), new MagickReadSettings { Format = MagickFormat.WebP });
        Assert.Equal((240u, 180u), (decoded.Width, decoded.Height));
        var pixels = decoded.GetPixels();
        Assert.True(Near(pixels.GetPixel(5, 5).ToColor(), MagickColors.OrangeRed), "background colour");
        Assert.True(Near(pixels.GetPixel(120, 90).ToColor(), MagickColors.Navy), "centre block colour");
    }

    [Fact]
    public async Task Heic_photos_are_decoded()
    {
        // A real HEIC (the encoder is not available here, so none is made).
        var heic = await File.ReadAllBytesAsync(Path.Combine(AppContext.BaseDirectory, "Fixtures", "sample.heic"));
        var url = await UploadAsync(heic, "IMG_0001.heic");

        var served = await api.Anonymous().GetAsync(new Uri(url).AbsolutePath);
        Assert.Equal("image/webp", served.Content.Headers.ContentType?.MediaType);
        using var decoded = new MagickImage(
            await served.Content.ReadAsByteArrayAsync(), new MagickReadSettings { Format = MagickFormat.WebP });
        Assert.Equal((12u, 7u), (decoded.Width, decoded.Height));
    }

    [Fact]
    public async Task A_big_photo_is_scaled_down_keeping_its_shape()
    {
        using var big = new MagickImage(MagickColors.OrangeRed, 2000, 1500);
        var url = await UploadAsync(Encode("png", big));

        var served = await api.Anonymous().GetAsync(new Uri(url).AbsolutePath);
        using var decoded = new MagickImage(await served.Content.ReadAsByteArrayAsync());
        Assert.Equal((1600u, 1200u), (decoded.Width, decoded.Height));
    }

    [Fact]
    public async Task A_photo_taken_sideways_is_turned_upright()
    {
        // 200x100 pixels that the camera says must be rotated (EXIF
        // orientation 6): it is really a portrait.
        using var sideways = Sample(200, 100);
        var exif = new ExifProfile();
        exif.SetValue(ExifTag.Orientation, (ushort)6);
        sideways.SetProfile(exif);
        // The JPEG writer takes the tag from this property, so both are needed
        // for a file that really carries orientation 6.
        sideways.Orientation = Orientation.RightTop;
        var url = await UploadAsync(Encode("jpeg", sideways));

        var served = await api.Anonymous().GetAsync(new Uri(url).AbsolutePath);
        using var decoded = new MagickImage(await served.Content.ReadAsByteArrayAsync());
        Assert.Equal((100u, 200u), (decoded.Width, decoded.Height));
    }

    [Fact]
    public async Task The_format_follows_the_bytes_not_the_file_name_or_declared_type()
    {
        // An AVIF that claims to be a PNG named .exe.
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Encode("avif"), "claims.exe", "image/png"));
        var uploaded = await response.ReadAsync<UploadedImageDto>();
        Assert.EndsWith(".webp", uploaded.Url);
    }

    // ---------------------------------------------------------- persistence

    [Fact]
    public async Task A_converted_photo_can_be_saved_on_a_dish_and_is_still_there_when_reopened()
    {
        var owner = await api.OwnerAsync();
        var url = await UploadAsync(Encode("avif"), "mutton.avif");

        var menu = await (await owner.GetAsync("/api/v1/admin/menu")).ReadAsync<MenuDto>();
        var dish = menu.Items.First();
        (await owner.PutAsJsonAsync(
            $"/api/v1/admin/menu/items/{dish.Id}",
            dish with { Image = url },
            DineQR.Api.Infrastructure.Json.Options)).EnsureSuccessStatusCode();

        // A brand-new client, as after refreshing or reopening the app: the
        // dish points at the photo, and the photo is served, byte for byte
        // the same every time.
        var guestMenu = await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();
        var savedUrl = guestMenu.Items.Single(i => i.Id == dish.Id).Image;
        Assert.Equal(url, savedUrl);

        var first = await api.Anonymous().GetAsync(new Uri(savedUrl).AbsolutePath);
        var second = await api.Anonymous().GetAsync(new Uri(savedUrl).AbsolutePath);
        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(await first.Content.ReadAsByteArrayAsync(), await second.Content.ReadAsByteArrayAsync());
    }

    [Fact]
    public async Task A_browser_that_already_has_the_photo_is_told_it_is_unchanged()
    {
        var url = await UploadAsync(Encode("png"));
        var path = new Uri(url).AbsolutePath;
        var first = await api.Anonymous().GetAsync(path);

        var request = new HttpRequestMessage(HttpMethod.Get, path);
        request.Headers.IfNoneMatch.Add(first.Headers.ETag!);
        var again = await api.Anonymous().SendAsync(request);
        Assert.Equal(HttpStatusCode.NotModified, again.StatusCode);
    }

    [Fact]
    public async Task Two_uploads_of_the_same_photo_do_not_collide()
    {
        var bytes = Encode("png");
        Assert.NotEqual(await UploadAsync(bytes), await UploadAsync(bytes));
    }

    [Theory]
    [InlineData("not-a-photo")]
    [InlineData("0123456789abcdef0123456789abcdef")] // well-formed, never stored
    [InlineData("0123456789abcdef0123456789abcdef.webp")]
    public async Task A_photo_that_does_not_exist_is_not_found(string file)
    {
        var response = await api.Anonymous().GetAsync($"/api/v1/images/{file}");
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    // ------------------------------------------------------------- refusals

    [Theory]
    [InlineData(new byte[] { 0x25, 0x50, 0x44, 0x46 })] // PDF
    [InlineData(new byte[] { 0x4D, 0x5A, 0x90, 0x00 })] // Windows executable
    [InlineData(new byte[] { 0x3C, 0x73, 0x76, 0x67 })] // <svg: scriptable, never a photo
    [InlineData(new byte[] { 0x68, 0x65, 0x6C, 0x6C, 0x6F })] // plain text
    public async Task A_file_that_is_not_an_accepted_image_is_refused(byte[] signature)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Padded(signature), "photo.png", "image/png"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("unsupportedImageType", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task The_refusal_names_the_formats_that_are_accepted()
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Padded([0x25, 0x50, 0x44, 0x46])));
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("AVIF", body);
        Assert.Contains("HEIC", body);
    }

    [Theory]
    [InlineData(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0 })] // JPEG header, nothing after it
    [InlineData(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A })] // PNG
    [InlineData(new byte[] { 0, 0, 0, 0x1C, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66 })] // AVIF
    [InlineData(new byte[] { 0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63 })] // HEIC
    public async Task A_file_that_only_starts_like_an_image_is_refused_as_damaged(byte[] header)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Padded(header)));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("invalidImage", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task A_photo_with_too_many_pixels_is_refused()
    {
        // 5 megapixels of one colour (the tests allow 4): a tiny file that
        // describes a much bigger picture.
        using var huge = new MagickImage(MagickColors.White, 2500, 2000);
        var bytes = Encode("png", huge);
        Assert.True(bytes.Length < ApiFactory.MaxUploadBytes, "the test file must itself be small");

        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(bytes));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("imageTooLarge", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task A_photo_over_the_size_limit_is_refused()
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Padded(Png, ApiFactory.MaxUploadBytes + 1)));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("fileTooLarge", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task An_empty_file_is_refused()
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form([]));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("noFile", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task Uploading_needs_a_signed_in_staff_member()
    {
        var response = await api.Anonymous().PostAsync(Url, Form(Encode("png")));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_role_without_ManageMenu_cannot_upload()
    {
        // Kitchen may view the menu but not change it.
        var kitchen = await api.NewStaffAsync("kitchen");
        var response = await kitchen.PostAsync(Url, Form(Encode("png")));
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    // ------------------------------------------------------------- sniffing

    [Theory]
    [InlineData("jpeg", new byte[] { 0xFF, 0xD8, 0xFF, 0xDB })]
    [InlineData("gif", new byte[] { 0x47, 0x49, 0x46, 0x38, 0x39, 0x61 })]
    [InlineData("tiff", new byte[] { 0x49, 0x49, 0x2A, 0x00 })]
    [InlineData("tiff", new byte[] { 0x4D, 0x4D, 0x00, 0x2A })]
    [InlineData("ico", new byte[] { 0x00, 0x00, 0x01, 0x00, 0x01, 0x00 })]
    public void Sniff_recognises_formats_by_their_leading_bytes(string expected, byte[] header) =>
        Assert.Equal(expected, ImageNormalizer.Sniff(header)?.Name);

    [Fact]
    public void Sniff_tells_avif_from_heic_by_the_brands_in_the_container()
    {
        static byte[] Box(string major, params string[] compatible)
        {
            var brands = new[] { major, "\0\0\0\0" }.Concat(compatible).Select(System.Text.Encoding.ASCII.GetBytes);
            var body = brands.SelectMany(b => b).ToArray();
            var size = 8 + body.Length;
            return [0, 0, 0, (byte)size, .. "ftyp"u8.ToArray(), .. body];
        }

        Assert.Equal("avif", ImageNormalizer.Sniff(Box("avif"))?.Name);
        Assert.Equal("avif", ImageNormalizer.Sniff(Box("avis"))?.Name);
        Assert.Equal("heic", ImageNormalizer.Sniff(Box("heic"))?.Name);
        // mif1 is shared by both; the compatible brands decide.
        Assert.Equal("avif", ImageNormalizer.Sniff(Box("mif1", "avif"))?.Name);
        Assert.Equal("heic", ImageNormalizer.Sniff(Box("mif1", "heic"))?.Name);
        // An MP4 video uses the same container but is not a photo.
        Assert.Null(ImageNormalizer.Sniff(Box("isom", "mp42")));
    }

    [Fact]
    public void Sniff_does_not_take_any_file_starting_with_BM_for_a_bitmap()
    {
        Assert.Null(ImageNormalizer.Sniff("BM is not a bitmap, just text"u8));
        Assert.Equal("bmp", ImageNormalizer.Sniff(Encode("bmp"))?.Name);
    }
}

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DineQR.Api.Contracts;

namespace DineQR.Api.Tests;

[Collection(ApiCollection.Name)]
public class ImageUploadTests(ApiFactory api)
{
    private const string Url = "/api/v1/admin/uploads/dish-images";

    /// A buffer that starts with [signature], padded to [length].
    private static byte[] Image(byte[] signature, int length = 256)
    {
        var bytes = new byte[length];
        signature.CopyTo(bytes, 0);
        return bytes;
    }

    private static readonly byte[] Png =
        [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0];

    /// Posts [bytes] as the `file` field of a multipart form.
    private static MultipartFormDataContent Form(
        byte[] bytes, string name = "photo.png", string contentType = "image/png")
    {
        var content = new ByteArrayContent(bytes);
        content.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        return new MultipartFormDataContent { { content, "file", name } };
    }

    [Fact]
    public async Task An_uploaded_photo_is_stored_and_served_back()
    {
        var owner = await api.OwnerAsync();
        var bytes = Image(Png);

        var response = await owner.PostAsync(Url, Form(bytes));
        var uploaded = await response.ReadAsync<UploadedImageDto>();

        Assert.StartsWith("http", uploaded.Url);
        Assert.Contains("/uploads/dishes/", uploaded.Url);
        Assert.EndsWith(".png", uploaded.Url);

        // The URL must be reachable without a token: the customer menu is
        // anonymous.
        var path = new Uri(uploaded.Url).AbsolutePath;
        var served = await api.Anonymous().GetAsync(path);
        Assert.Equal(HttpStatusCode.OK, served.StatusCode);
        Assert.Equal("image/png", served.Content.Headers.ContentType?.MediaType);
        Assert.Equal(bytes, await served.Content.ReadAsByteArrayAsync());
    }

    [Fact]
    public async Task Two_uploads_of_the_same_photo_do_not_collide()
    {
        var owner = await api.OwnerAsync();
        var first = await (await owner.PostAsync(Url, Form(Image(Png)))).ReadAsync<UploadedImageDto>();
        var second = await (await owner.PostAsync(Url, Form(Image(Png)))).ReadAsync<UploadedImageDto>();
        Assert.NotEqual(first.Url, second.Url);
    }

    [Fact]
    public async Task The_extension_follows_the_bytes_not_the_file_name()
    {
        var owner = await api.OwnerAsync();
        // A JPEG that the client claims is a PNG.
        var response = await owner.PostAsync(Url, Form(Image(Jpeg), "claims.png", "image/png"));
        var uploaded = await response.ReadAsync<UploadedImageDto>();
        Assert.EndsWith(".jpg", uploaded.Url);
    }

    [Theory]
    [InlineData(new byte[] { 0x47, 0x49, 0x46, 0x38 })] // GIF
    [InlineData(new byte[] { 0x25, 0x50, 0x44, 0x46 })] // PDF
    [InlineData(new byte[] { 0x4D, 0x5A, 0x90, 0x00 })] // Windows executable
    public async Task A_file_that_is_not_an_accepted_image_is_refused(byte[] signature)
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Image(signature), "photo.png"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal("unsupportedImageType", await response.ErrorCodeAsync());
    }

    [Fact]
    public async Task A_photo_over_the_size_limit_is_refused()
    {
        var owner = await api.OwnerAsync();
        var response = await owner.PostAsync(Url, Form(Image(Png, ApiFactory.MaxUploadBytes + 1)));
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
        var response = await api.Anonymous().PostAsync(Url, Form(Image(Png)));
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task A_role_without_ManageMenu_cannot_upload()
    {
        // Kitchen may view the menu but not change it.
        var kitchen = await api.NewStaffAsync("kitchen");
        var response = await kitchen.PostAsync(Url, Form(Image(Png)));
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task An_uploaded_photo_can_be_saved_on_a_dish_and_served_to_guests()
    {
        var owner = await api.OwnerAsync();
        var uploaded = await (await owner.PostAsync(Url, Form(Image(Png)))).ReadAsync<UploadedImageDto>();

        var menu = await (await owner.GetAsync("/api/v1/admin/menu")).ReadAsync<MenuDto>();
        var dish = menu.Items.First();
        var saved = await owner.PutAsJsonAsync(
            $"/api/v1/admin/menu/items/{dish.Id}",
            dish with { Image = uploaded.Url },
            DineQR.Api.Infrastructure.Json.Options);
        saved.EnsureSuccessStatusCode();

        // The upload URL survives validation and reaches the public menu.
        var guestMenu = await (await api.Anonymous().GetAsync("/api/v1/menu")).ReadAsync<MenuDto>();
        Assert.Equal(uploaded.Url, guestMenu.Items.Single(i => i.Id == dish.Id).Image);
    }
}

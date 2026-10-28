using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class StoredImageKind : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "kind",
                table: "stored_images",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                // Every image stored before this was a dish photo.
                defaultValue: "dish");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "kind",
                table: "stored_images");
        }
    }
}

using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class DishBanner : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "is_featured",
                table: "menu_items",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "is_featured",
                table: "menu_items");
        }
    }
}

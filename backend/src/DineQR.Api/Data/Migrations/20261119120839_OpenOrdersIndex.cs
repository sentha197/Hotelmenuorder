using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class OpenOrdersIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateIndex(
                name: "ix_orders_open_created_at",
                table: "orders",
                column: "created_at",
                filter: "status <> 'served' AND status <> 'cancelled'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_orders_open_created_at",
                table: "orders");
        }
    }
}

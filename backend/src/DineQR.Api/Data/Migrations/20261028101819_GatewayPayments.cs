using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class GatewayPayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "expires_at",
                table: "payments",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "provider_payment_id",
                table: "payments",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_payments_provider_order_id",
                table: "payments",
                column: "provider_order_id",
                filter: "provider_order_id is not null");

            migrationBuilder.CreateIndex(
                name: "ix_payments_provider_provider_payment_id",
                table: "payments",
                columns: new[] { "provider", "provider_payment_id" },
                unique: true,
                filter: "provider_payment_id is not null");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_payments_provider_order_id",
                table: "payments");

            migrationBuilder.DropIndex(
                name: "ix_payments_provider_provider_payment_id",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "expires_at",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "provider_payment_id",
                table: "payments");
        }
    }
}

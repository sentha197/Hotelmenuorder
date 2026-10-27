using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddUpiPayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "upi_enabled",
                table: "restaurant_settings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "upi_id",
                table: "restaurant_settings",
                type: "character varying(100)",
                maxLength: 100,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "upi_payee_name",
                table: "restaurant_settings",
                type: "character varying(60)",
                maxLength: 60,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "upi_qr_image",
                table: "restaurant_settings",
                type: "character varying(500)",
                maxLength: 500,
                nullable: false,
                defaultValue: "");

            // "manual", not the generated "": the existing settings row gets
            // this value, and an empty string is not a mode the app can read.
            migrationBuilder.AddColumn<string>(
                name: "upi_verification_mode",
                table: "restaurant_settings",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "manual");

            migrationBuilder.AddColumn<DateTime>(
                name: "claimed_at",
                table: "payments",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "ix_payments_upi_reference",
                table: "payments",
                column: "reference",
                unique: true,
                filter: "provider = 'UPI direct' and status = 'succeeded'");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_payments_upi_reference",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "upi_enabled",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "upi_id",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "upi_payee_name",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "upi_qr_image",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "upi_verification_mode",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "claimed_at",
                table: "payments");
        }
    }
}

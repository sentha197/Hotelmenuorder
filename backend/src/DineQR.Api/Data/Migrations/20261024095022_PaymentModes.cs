using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class PaymentModes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Existing data: every amount so far was in rupees, and the
            // restaurant starts in demo mode (live needs a verified gateway).
            // Earlier payments keep is_simulated as recorded.
            migrationBuilder.AddColumn<string>(
                name: "currency",
                table: "restaurant_settings",
                type: "character varying(3)",
                maxLength: 3,
                nullable: false,
                defaultValue: "INR");

            migrationBuilder.AddColumn<string>(
                name: "payment_mode",
                table: "restaurant_settings",
                type: "character varying(20)",
                maxLength: 20,
                nullable: false,
                defaultValue: "demo");

            migrationBuilder.AddColumn<string>(
                name: "currency",
                table: "payments",
                type: "character varying(3)",
                maxLength: 3,
                nullable: false,
                defaultValue: "INR");

            migrationBuilder.AddColumn<string>(
                name: "method_detail",
                table: "payments",
                type: "character varying(40)",
                maxLength: 40,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<string>(
                name: "counter_request",
                table: "invoices",
                type: "character varying(20)",
                maxLength: 20,
                nullable: true);

            migrationBuilder.AddColumn<decimal>(
                name: "counter_request_amount",
                table: "invoices",
                type: "numeric(14,2)",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "counter_requested_at",
                table: "invoices",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "currency",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "payment_mode",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "currency",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "method_detail",
                table: "payments");

            migrationBuilder.DropColumn(
                name: "counter_request",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "counter_request_amount",
                table: "invoices");

            migrationBuilder.DropColumn(
                name: "counter_requested_at",
                table: "invoices");
        }
    }
}

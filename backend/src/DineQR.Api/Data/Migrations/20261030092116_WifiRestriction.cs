using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class WifiRestriction : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "wifi_restrict_takeaway",
                table: "restaurant_settings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "wifi_restriction_enabled",
                table: "restaurant_settings",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "wifi_ssid",
                table: "restaurant_settings",
                type: "character varying(32)",
                maxLength: 32,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateTable(
                name: "authorized_networks",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    settings_id = table.Column<int>(type: "integer", nullable: false),
                    value = table.Column<string>(type: "character varying(253)", maxLength: 253, nullable: false),
                    label = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_by_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_authorized_networks", x => x.id);
                    table.ForeignKey(
                        name: "fk_authorized_networks_restaurant_settings_settings_id",
                        column: x => x.settings_id,
                        principalTable: "restaurant_settings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "guest_sessions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    settings_id = table.Column<int>(type: "integer", nullable: false),
                    table_number = table.Column<int>(type: "integer", nullable: true),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    expires_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    verified_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    status_changed_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_guest_sessions", x => x.id);
                    table.ForeignKey(
                        name: "fk_guest_sessions_restaurant_settings_settings_id",
                        column: x => x.settings_id,
                        principalTable: "restaurant_settings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_guest_sessions_restaurant_tables_table_number",
                        column: x => x.table_number,
                        principalTable: "restaurant_tables",
                        principalColumn: "number",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "ix_authorized_networks_settings_id_value",
                table: "authorized_networks",
                columns: new[] { "settings_id", "value" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_guest_sessions_expires_at",
                table: "guest_sessions",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_guest_sessions_settings_id",
                table: "guest_sessions",
                column: "settings_id");

            migrationBuilder.CreateIndex(
                name: "ix_guest_sessions_table_number_status",
                table: "guest_sessions",
                columns: new[] { "table_number", "status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "authorized_networks");

            migrationBuilder.DropTable(
                name: "guest_sessions");

            migrationBuilder.DropColumn(
                name: "wifi_restrict_takeaway",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "wifi_restriction_enabled",
                table: "restaurant_settings");

            migrationBuilder.DropColumn(
                name: "wifi_ssid",
                table: "restaurant_settings");
        }
    }
}

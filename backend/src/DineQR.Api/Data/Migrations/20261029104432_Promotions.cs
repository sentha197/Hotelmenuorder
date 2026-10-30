using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class Promotions : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "discounts",
                table: "orders",
                type: "jsonb",
                nullable: false,
                defaultValueSql: "'[]'::jsonb");

            migrationBuilder.AddColumn<string>(
                name: "combo_id",
                table: "order_lines",
                type: "character varying(40)",
                maxLength: 40,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "combo_items",
                table: "order_lines",
                type: "jsonb",
                nullable: false,
                defaultValueSql: "'[]'::jsonb");

            migrationBuilder.AddColumn<decimal>(
                name: "discount",
                table: "order_lines",
                type: "numeric(14,2)",
                nullable: false,
                defaultValue: 0m);

            migrationBuilder.AddColumn<string>(
                name: "discount_label",
                table: "order_lines",
                type: "character varying(80)",
                maxLength: 80,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "promotion_id",
                table: "order_lines",
                type: "character varying(40)",
                maxLength: 40,
                nullable: true);

            migrationBuilder.AddColumn<DateOnly>(
                name: "ends_on",
                table: "discount_offers",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<DateOnly>(
                name: "starts_on",
                table: "discount_offers",
                type: "date",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "usage_limit",
                table: "discount_offers",
                type: "integer",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "used_count",
                table: "discount_offers",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateTable(
                name: "promotions",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    title = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    description = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    image = table.Column<string>(type: "text", nullable: false),
                    starts_on = table.Column<DateOnly>(type: "date", nullable: true),
                    ends_on = table.Column<DateOnly>(type: "date", nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    usage_limit = table.Column<int>(type: "integer", nullable: true),
                    used_count = table.Column<int>(type: "integer", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    discount_type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    discount_value = table.Column<int>(type: "integer", nullable: false),
                    combo_price = table.Column<decimal>(type: "numeric(14,2)", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_promotions", x => x.id);
                    table.CheckConstraint("ck_promotions_discount_value", "discount_value >= 0");
                    table.CheckConstraint("ck_promotions_used_count", "used_count >= 0");
                });

            migrationBuilder.CreateTable(
                name: "promotion_items",
                columns: table => new
                {
                    promotion_id = table.Column<string>(type: "character varying(40)", nullable: false),
                    item_id = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    quantity = table.Column<int>(type: "integer", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_promotion_items", x => new { x.promotion_id, x.item_id });
                    table.CheckConstraint("ck_promotion_items_quantity", "quantity between 1 and 10");
                    table.ForeignKey(
                        name: "fk_promotion_items_menu_items_item_id",
                        column: x => x.item_id,
                        principalTable: "menu_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_promotion_items_promotions_promotion_id",
                        column: x => x.promotion_id,
                        principalTable: "promotions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.AddCheckConstraint(
                name: "ck_discount_offers_used_count",
                table: "discount_offers",
                sql: "used_count >= 0");

            migrationBuilder.CreateIndex(
                name: "ix_promotion_items_item_id",
                table: "promotion_items",
                column: "item_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "promotion_items");

            migrationBuilder.DropTable(
                name: "promotions");

            migrationBuilder.DropCheckConstraint(
                name: "ck_discount_offers_used_count",
                table: "discount_offers");

            migrationBuilder.DropColumn(
                name: "discounts",
                table: "orders");

            migrationBuilder.DropColumn(
                name: "combo_id",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "combo_items",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "discount",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "discount_label",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "promotion_id",
                table: "order_lines");

            migrationBuilder.DropColumn(
                name: "ends_on",
                table: "discount_offers");

            migrationBuilder.DropColumn(
                name: "starts_on",
                table: "discount_offers");

            migrationBuilder.DropColumn(
                name: "usage_limit",
                table: "discount_offers");

            migrationBuilder.DropColumn(
                name: "used_count",
                table: "discount_offers");
        }
    }
}

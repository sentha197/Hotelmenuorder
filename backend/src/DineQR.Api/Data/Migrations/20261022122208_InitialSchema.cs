using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // The `users` table already exists in the dineqr database and is
            // adopted rather than created by EF (it is excluded from the
            // model's migrations). A fresh database (tests, new installs) gets
            // the same definition. Existing rows are never touched: the three
            // sign-in columns are only added when missing.
            migrationBuilder.Sql("""
                CREATE TABLE IF NOT EXISTS users (
                    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                    full_name character varying(150) NOT NULL,
                    email character varying(255) NOT NULL CONSTRAINT users_email_key UNIQUE,
                    phone character varying(20),
                    password_hash text NOT NULL,
                    role character varying(50) NOT NULL DEFAULT 'User',
                    is_active boolean NOT NULL DEFAULT true,
                    created_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at timestamp with time zone NULL;
                ALTER TABLE users ADD COLUMN IF NOT EXISTS failed_login_count integer NOT NULL DEFAULT 0;
                ALTER TABLE users ADD COLUMN IF NOT EXISTS locked_until timestamp with time zone NULL;
                """);

            migrationBuilder.CreateSequence(
                name: "inventory_item_seq");

            migrationBuilder.CreateSequence(
                name: "invoice_number_seq");

            migrationBuilder.CreateSequence(
                name: "order_number_seq",
                startValue: 12345L);

            migrationBuilder.CreateSequence(
                name: "payment_number_seq");

            migrationBuilder.CreateSequence(
                name: "refund_number_seq");

            migrationBuilder.CreateTable(
                name: "audit_logs",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    actor_id = table.Column<long>(type: "bigint", nullable: true),
                    actor_name = table.Column<string>(type: "text", nullable: false),
                    actor_role = table.Column<string>(type: "text", nullable: false),
                    action = table.Column<string>(type: "text", nullable: false),
                    summary = table.Column<string>(type: "text", nullable: false),
                    target_id = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_audit_logs", x => x.id);
                    table.ForeignKey(
                        name: "fk_audit_logs_users_actor_id",
                        column: x => x.actor_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "discount_offers",
                columns: table => new
                {
                    code = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    title = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    type = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    value = table.Column<int>(type: "integer", nullable: false),
                    min_subtotal = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    max_discount = table.Column<decimal>(type: "numeric(14,2)", nullable: true),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_discount_offers", x => x.code);
                    table.CheckConstraint("ck_discount_offers_value", "value >= 0");
                });

            migrationBuilder.CreateTable(
                name: "inventory_items",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    unit = table.Column<string>(type: "text", nullable: false),
                    quantity = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: false),
                    reorder_level = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: false),
                    supplier = table.Column<string>(type: "text", nullable: false),
                    linked_dish_ids = table.Column<List<string>>(type: "text[]", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_inventory_items", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "menu_categories",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    label = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    cover_image = table.Column<string>(type: "text", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_menu_categories", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "orders",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    table_number = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    source = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    special_instructions = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    estimated_ready_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    subtotal = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    discount = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    discount_label = table.Column<string>(type: "text", nullable: true),
                    service_charge = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    service_charge_basis_points = table.Column<int>(type: "integer", nullable: false),
                    tax = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    tax_rate_basis_points = table.Column<int>(type: "integer", nullable: false),
                    tax_name = table.Column<string>(type: "text", nullable: false),
                    total = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    offer_code = table.Column<string>(type: "text", nullable: true),
                    idempotency_key = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    guest_session_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_by_user_id = table.Column<long>(type: "bigint", nullable: true),
                    cancel_reason = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    feedback_rating = table.Column<int>(type: "integer", nullable: true),
                    feedback_comment = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: true),
                    feedback_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_orders", x => x.id);
                    table.CheckConstraint("ck_orders_total", "total >= 0");
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    user_id = table.Column<long>(type: "bigint", nullable: false),
                    session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    expires_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    session_expires_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    revoked_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refresh_tokens", x => x.id);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "restaurant_settings",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false),
                    name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    phone = table.Column<string>(type: "text", nullable: false),
                    email = table.Column<string>(type: "text", nullable: false),
                    address = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    tax_registration = table.Column<string>(type: "text", nullable: false),
                    tax_name = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    tax_rate_basis_points = table.Column<int>(type: "integer", nullable: false),
                    service_charge_basis_points = table.Column<int>(type: "integer", nullable: false),
                    utc_offset_minutes = table.Column<int>(type: "integer", nullable: false),
                    allow_partial_payments = table.Column<bool>(type: "boolean", nullable: false),
                    online_methods = table.Column<List<string>>(type: "text[]", nullable: false),
                    receipt_footer = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    show_sold_out_dishes = table.Column<bool>(type: "boolean", nullable: false),
                    auto_unavailable_when_out_of_stock = table.Column<bool>(type: "boolean", nullable: false),
                    prep_buffer_minutes = table.Column<int>(type: "integer", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_restaurant_settings", x => x.id);
                    table.CheckConstraint("ck_restaurant_settings_singleton", "id = 1");
                });

            migrationBuilder.CreateTable(
                name: "restaurant_tables",
                columns: table => new
                {
                    number = table.Column<int>(type: "integer", nullable: false),
                    seats = table.Column<int>(type: "integer", nullable: false),
                    area = table.Column<string>(type: "character varying(24)", maxLength: 24, nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    assigned_staff_id = table.Column<long>(type: "bigint", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_restaurant_tables", x => x.number);
                    table.CheckConstraint("ck_restaurant_tables_number", "number between 1 and 999");
                    table.CheckConstraint("ck_restaurant_tables_seats", "seats between 1 and 30");
                    table.ForeignKey(
                        name: "fk_restaurant_tables_users_assigned_staff_id",
                        column: x => x.assigned_staff_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "stock_movements",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    item_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    change = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: false),
                    balance = table.Column<decimal>(type: "numeric(12,3)", precision: 12, scale: 3, nullable: false),
                    reason = table.Column<string>(type: "text", nullable: false),
                    at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    by_user_id = table.Column<long>(type: "bigint", nullable: true),
                    by_name = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_stock_movements", x => x.id);
                    table.ForeignKey(
                        name: "fk_stock_movements_inventory_items_item_id",
                        column: x => x.item_id,
                        principalTable: "inventory_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "menu_items",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    category_id = table.Column<string>(type: "character varying(40)", nullable: false),
                    name = table.Column<string>(type: "character varying(60)", maxLength: 60, nullable: false),
                    description = table.Column<string>(type: "character varying(400)", maxLength: 400, nullable: false),
                    short_description = table.Column<string>(type: "character varying(80)", maxLength: 80, nullable: false),
                    price = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    image = table.Column<string>(type: "text", nullable: false),
                    gallery = table.Column<List<string>>(type: "text[]", nullable: false),
                    is_veg = table.Column<bool>(type: "boolean", nullable: false),
                    rating = table.Column<double>(type: "double precision", nullable: false),
                    review_count = table.Column<int>(type: "integer", nullable: false),
                    is_popular = table.Column<bool>(type: "boolean", nullable: false),
                    is_chef_special = table.Column<bool>(type: "boolean", nullable: false),
                    has_spice_level = table.Column<bool>(type: "boolean", nullable: false),
                    default_spice = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    prep_minutes = table.Column<int>(type: "integer", nullable: false),
                    is_available = table.Column<bool>(type: "boolean", nullable: false),
                    is_archived = table.Column<bool>(type: "boolean", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_menu_items", x => x.id);
                    table.CheckConstraint("ck_menu_items_price", "price >= 0");
                    table.ForeignKey(
                        name: "fk_menu_items_categories_category_id",
                        column: x => x.category_id,
                        principalTable: "menu_categories",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "invoices",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    bill_number = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    order_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    table_number = table.Column<int>(type: "integer", nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    subtotal = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    discount = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    discount_label = table.Column<string>(type: "text", nullable: true),
                    service_charge = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    service_charge_basis_points = table.Column<int>(type: "integer", nullable: false),
                    tax = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    tax_rate_basis_points = table.Column<int>(type: "integer", nullable: false),
                    tax_name = table.Column<string>(type: "text", nullable: false),
                    total = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    restaurant_name = table.Column<string>(type: "text", nullable: false),
                    restaurant_phone = table.Column<string>(type: "text", nullable: false),
                    restaurant_email = table.Column<string>(type: "text", nullable: false),
                    restaurant_address = table.Column<string>(type: "text", nullable: false),
                    restaurant_tax_registration = table.Column<string>(type: "text", nullable: false),
                    receipt_footer = table.Column<string>(type: "text", nullable: false),
                    is_void = table.Column<bool>(type: "boolean", nullable: false),
                    void_reason = table.Column<string>(type: "text", nullable: false),
                    voided_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    is_settled = table.Column<bool>(type: "boolean", nullable: false),
                    xmin = table.Column<uint>(type: "xid", rowVersion: true, nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_invoices", x => x.id);
                    table.ForeignKey(
                        name: "fk_invoices_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "order_lines",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    line_no = table.Column<int>(type: "integer", nullable: false),
                    item_id = table.Column<string>(type: "text", nullable: false),
                    name = table.Column<string>(type: "text", nullable: false),
                    image = table.Column<string>(type: "text", nullable: false),
                    is_veg = table.Column<bool>(type: "boolean", nullable: false),
                    unit_price = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    quantity = table.Column<int>(type: "integer", nullable: false),
                    options = table.Column<List<string>>(type: "text[]", nullable: false),
                    category_id = table.Column<string>(type: "text", nullable: false),
                    category_name = table.Column<string>(type: "text", nullable: false),
                    portion_id = table.Column<string>(type: "text", nullable: true),
                    spice = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    add_on_ids = table.Column<List<string>>(type: "text[]", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_order_lines", x => x.id);
                    table.CheckConstraint("ck_order_lines_quantity", "quantity between 1 and 20");
                    table.ForeignKey(
                        name: "fk_order_lines_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "order_status_history",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    order_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    changed_by_user_id = table.Column<long>(type: "bigint", nullable: true),
                    changed_by_name = table.Column<string>(type: "text", nullable: false),
                    reason = table.Column<string>(type: "text", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_order_status_history", x => x.id);
                    table.ForeignKey(
                        name: "fk_order_status_history_orders_order_id",
                        column: x => x.order_id,
                        principalTable: "orders",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "menu_item_add_ons",
                columns: table => new
                {
                    item_id = table.Column<string>(type: "character varying(60)", nullable: false),
                    id = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    name = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    price = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    sort_order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_menu_item_add_ons", x => new { x.item_id, x.id });
                    table.ForeignKey(
                        name: "fk_menu_item_add_ons_menu_items_item_id",
                        column: x => x.item_id,
                        principalTable: "menu_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "menu_item_portions",
                columns: table => new
                {
                    item_id = table.Column<string>(type: "character varying(60)", nullable: false),
                    id = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    label = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    extra_price = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    detail = table.Column<string>(type: "text", nullable: true),
                    sort_order = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_menu_item_portions", x => new { x.item_id, x.id });
                    table.ForeignKey(
                        name: "fk_menu_item_portions_menu_items_item_id",
                        column: x => x.item_id,
                        principalTable: "menu_items",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "payments",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    invoice_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    order_id = table.Column<string>(type: "text", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    method = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    provider = table.Column<string>(type: "character varying(40)", maxLength: 40, nullable: false),
                    provider_order_id = table.Column<string>(type: "text", nullable: true),
                    reference = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    failure_reason = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    idempotency_key = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    is_simulated = table.Column<bool>(type: "boolean", nullable: false),
                    recorded_by_user_id = table.Column<long>(type: "bigint", nullable: true),
                    recorded_by_name = table.Column<string>(type: "text", nullable: false),
                    guest_session_id = table.Column<Guid>(type: "uuid", nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    confirmed_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_payments", x => x.id);
                    table.CheckConstraint("ck_payments_amount", "amount > 0");
                    table.ForeignKey(
                        name: "fk_payments_invoices_invoice_id",
                        column: x => x.invoice_id,
                        principalTable: "invoices",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "refunds",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    invoice_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    payment_id = table.Column<string>(type: "character varying(20)", nullable: false),
                    amount = table.Column<decimal>(type: "numeric(14,2)", nullable: false),
                    reason = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    reference = table.Column<string>(type: "text", nullable: false),
                    is_simulated = table.Column<bool>(type: "boolean", nullable: false),
                    processed_by_user_id = table.Column<long>(type: "bigint", nullable: true),
                    processed_by_name = table.Column<string>(type: "text", nullable: false),
                    idempotency_key = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refunds", x => x.id);
                    table.CheckConstraint("ck_refunds_amount", "amount > 0");
                    table.ForeignKey(
                        name: "fk_refunds_invoices_invoice_id",
                        column: x => x.invoice_id,
                        principalTable: "invoices",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_refunds_payments_payment_id",
                        column: x => x.payment_id,
                        principalTable: "payments",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "ix_audit_logs_action",
                table: "audit_logs",
                column: "action");

            migrationBuilder.CreateIndex(
                name: "ix_audit_logs_actor_id",
                table: "audit_logs",
                column: "actor_id");

            migrationBuilder.CreateIndex(
                name: "ix_audit_logs_at",
                table: "audit_logs",
                column: "at");

            migrationBuilder.CreateIndex(
                name: "ix_invoices_bill_number",
                table: "invoices",
                column: "bill_number",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_invoices_created_at",
                table: "invoices",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "ix_invoices_is_settled",
                table: "invoices",
                column: "is_settled");

            migrationBuilder.CreateIndex(
                name: "ix_invoices_order_id",
                table: "invoices",
                column: "order_id",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_menu_items_category_id",
                table: "menu_items",
                column: "category_id");

            migrationBuilder.CreateIndex(
                name: "ix_order_lines_order_id_line_no",
                table: "order_lines",
                columns: new[] { "order_id", "line_no" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_order_status_history_order_id_at",
                table: "order_status_history",
                columns: new[] { "order_id", "at" });

            migrationBuilder.CreateIndex(
                name: "ix_orders_created_at",
                table: "orders",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "ix_orders_guest_session_id",
                table: "orders",
                column: "guest_session_id");

            migrationBuilder.CreateIndex(
                name: "ix_orders_idempotency_key",
                table: "orders",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_orders_status",
                table: "orders",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_orders_table_number",
                table: "orders",
                column: "table_number");

            migrationBuilder.CreateIndex(
                name: "ix_payments_created_at",
                table: "payments",
                column: "created_at");

            migrationBuilder.CreateIndex(
                name: "ix_payments_idempotency_key",
                table: "payments",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_payments_invoice_id",
                table: "payments",
                column: "invoice_id");

            migrationBuilder.CreateIndex(
                name: "ix_payments_status",
                table: "payments",
                column: "status");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_session_id",
                table: "refresh_tokens",
                column: "session_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_token_hash",
                table: "refresh_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_user_id",
                table: "refresh_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ix_refunds_idempotency_key",
                table: "refunds",
                column: "idempotency_key",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_refunds_invoice_id",
                table: "refunds",
                column: "invoice_id");

            migrationBuilder.CreateIndex(
                name: "ix_refunds_payment_id",
                table: "refunds",
                column: "payment_id");

            migrationBuilder.CreateIndex(
                name: "ix_restaurant_tables_assigned_staff_id",
                table: "restaurant_tables",
                column: "assigned_staff_id");

            migrationBuilder.CreateIndex(
                name: "ix_stock_movements_item_id_at",
                table: "stock_movements",
                columns: new[] { "item_id", "at" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "audit_logs");

            migrationBuilder.DropTable(
                name: "discount_offers");

            migrationBuilder.DropTable(
                name: "menu_item_add_ons");

            migrationBuilder.DropTable(
                name: "menu_item_portions");

            migrationBuilder.DropTable(
                name: "order_lines");

            migrationBuilder.DropTable(
                name: "order_status_history");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "refunds");

            migrationBuilder.DropTable(
                name: "restaurant_settings");

            migrationBuilder.DropTable(
                name: "restaurant_tables");

            migrationBuilder.DropTable(
                name: "stock_movements");

            migrationBuilder.DropTable(
                name: "menu_items");

            migrationBuilder.DropTable(
                name: "payments");

            migrationBuilder.DropTable(
                name: "inventory_items");

            migrationBuilder.DropTable(
                name: "menu_categories");

            migrationBuilder.DropTable(
                name: "invoices");

            migrationBuilder.DropTable(
                name: "orders");

            migrationBuilder.DropSequence(
                name: "inventory_item_seq");

            migrationBuilder.DropSequence(
                name: "invoice_number_seq");

            migrationBuilder.DropSequence(
                name: "order_number_seq");

            migrationBuilder.DropSequence(
                name: "payment_number_seq");

            migrationBuilder.DropSequence(
                name: "refund_number_seq");

            // The adopted users table stays; only the columns added above go.
            migrationBuilder.Sql("""
                ALTER TABLE users DROP COLUMN IF EXISTS locked_until;
                ALTER TABLE users DROP COLUMN IF EXISTS failed_login_count;
                ALTER TABLE users DROP COLUMN IF EXISTS last_login_at;
                """);
        }
    }
}

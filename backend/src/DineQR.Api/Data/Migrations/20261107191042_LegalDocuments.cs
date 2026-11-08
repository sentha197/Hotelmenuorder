using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class LegalDocuments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "legal_documents",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    settings_id = table.Column<int>(type: "integer", nullable: false),
                    kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    title = table.Column<string>(type: "character varying(120)", maxLength: 120, nullable: false),
                    body = table.Column<string>(type: "character varying(60000)", maxLength: 60000, nullable: false),
                    change_summary = table.Column<string>(type: "character varying(300)", maxLength: 300, nullable: false),
                    requires_reacceptance = table.Column<bool>(type: "boolean", nullable: false),
                    status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    created_by_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    updated_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    updated_by_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    published_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    published_by_name = table.Column<string>(type: "character varying(150)", maxLength: 150, nullable: false),
                    retired_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_legal_documents", x => x.id);
                    table.CheckConstraint("ck_legal_documents_version", "version >= 1");
                    table.ForeignKey(
                        name: "fk_legal_documents_restaurant_settings_settings_id",
                        column: x => x.settings_id,
                        principalTable: "restaurant_settings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "legal_acceptances",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityAlwaysColumn),
                    settings_id = table.Column<int>(type: "integer", nullable: false),
                    guest_session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    table_number = table.Column<int>(type: "integer", nullable: true),
                    document_id = table.Column<long>(type: "bigint", nullable: false),
                    kind = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    accepted = table.Column<bool>(type: "boolean", nullable: false),
                    accepted_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_legal_acceptances", x => x.id);
                    table.ForeignKey(
                        name: "fk_legal_acceptances_guest_sessions_guest_session_id",
                        column: x => x.guest_session_id,
                        principalTable: "guest_sessions",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_legal_acceptances_legal_documents_document_id",
                        column: x => x.document_id,
                        principalTable: "legal_documents",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "fk_legal_acceptances_restaurant_settings_settings_id",
                        column: x => x.settings_id,
                        principalTable: "restaurant_settings",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_legal_acceptances_document_id",
                table: "legal_acceptances",
                column: "document_id");

            migrationBuilder.CreateIndex(
                name: "ix_legal_acceptances_guest_session_id_document_id",
                table: "legal_acceptances",
                columns: new[] { "guest_session_id", "document_id" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_legal_acceptances_settings_id_accepted_at",
                table: "legal_acceptances",
                columns: new[] { "settings_id", "accepted_at" });

            migrationBuilder.CreateIndex(
                name: "ix_legal_documents_one_published",
                table: "legal_documents",
                columns: new[] { "settings_id", "kind" },
                unique: true,
                filter: "status = 'published'");

            migrationBuilder.CreateIndex(
                name: "ix_legal_documents_settings_id_kind_version",
                table: "legal_documents",
                columns: new[] { "settings_id", "kind", "version" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "legal_acceptances");

            migrationBuilder.DropTable(
                name: "legal_documents");
        }
    }
}

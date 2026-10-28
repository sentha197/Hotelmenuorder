using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class StaffCustomAccess : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // `users` is adopted rather than created by EF (it is excluded from
            // migrations), so its new column is added by hand. Existing rows
            // stay NULL, which means "use the role's permissions".
            migrationBuilder.Sql("""
                ALTER TABLE users ADD COLUMN IF NOT EXISTS custom_permissions character varying(1000) NULL;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                ALTER TABLE users DROP COLUMN IF EXISTS custom_permissions;
                """);
        }
    }
}

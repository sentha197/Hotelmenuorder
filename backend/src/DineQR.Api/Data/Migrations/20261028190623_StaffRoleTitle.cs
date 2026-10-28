using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class StaffRoleTitle : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // `users` is adopted rather than created by EF (it is excluded from
            // migrations), so its new column is added by hand. Existing rows
            // stay NULL: only a custom role has a name of its own.
            migrationBuilder.Sql("""
                ALTER TABLE users ADD COLUMN IF NOT EXISTS role_title character varying(50) NULL;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                ALTER TABLE users DROP COLUMN IF EXISTS role_title;
                """);
        }
    }
}

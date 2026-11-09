using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <summary>
    /// UPI and QR become separate payment options, and demo mode is gone.
    /// Data only: no column is added or dropped. `payment_mode` is no longer
    /// mapped but stays in the table, so an older API still running while
    /// this one is deployed keeps working.
    /// </summary>
    public partial class SeparateUpiAndQr : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // "UPI and QR Payment" was one option stored as "upi": a
            // restaurant that offered it keeps offering both.
            migrationBuilder.Sql(
                """
                UPDATE restaurant_settings
                SET online_methods = array_append(online_methods, 'qr')
                WHERE 'upi' = ANY(online_methods) AND NOT ('qr' = ANY(online_methods));
                """);

            // Payments the removed demo simulator started and never finished
            // would hold their bills forever: nothing can finish them now. No
            // money moved for them.
            migrationBuilder.Sql(
                """
                UPDATE payments
                SET status = 'failed',
                    failure_reason = 'This payment was not completed. No money moved.',
                    updated_at = now(),
                    confirmed_at = now()
                WHERE provider = 'Simulator' AND status = 'pending';
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // An older API knows only "upi" (meaning both); it ignores "qr".
            migrationBuilder.Sql(
                """
                UPDATE restaurant_settings
                SET online_methods = array_remove(online_methods, 'qr');
                """);
        }
    }
}

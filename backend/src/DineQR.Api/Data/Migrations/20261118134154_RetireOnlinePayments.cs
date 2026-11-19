using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DineQR.Api.Data.Migrations
{
    /// <summary>
    /// Online payment is retired: guests order through DineQR and pay at the
    /// restaurant's billing counter. Data only, no schema change: every table
    /// and column (payments, refunds, the old UPI settings) is kept, and no
    /// completed payment or refund is touched.
    ///
    /// - The online options and UPI-to-the-restaurant switch are turned off,
    ///   so an older API still running during the deploy offers nothing online.
    /// - Online payments still waiting for an outcome can never get one now
    ///   (no gateway, no cashier verification screen), and a pending payment
    ///   would hold its bill. They are closed as cancelled with a reason that
    ///   says what to do; if the guest did pay, the cashier records it at the
    ///   counter with the UPI reference.
    /// - Guests' "I will pay at the counter" notices are cleared: every guest
    ///   pays at the counter now.
    /// </summary>
    public partial class RetireOnlinePayments : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                UPDATE restaurant_settings
                SET online_methods = '{}',
                    upi_enabled = false;
                """);
            migrationBuilder.Sql("""
                UPDATE payments
                SET status = 'cancelled',
                    failure_reason = 'Online payment was retired before this was confirmed. Collect the bill at the counter.',
                    updated_at = now(),
                    confirmed_at = now()
                WHERE status = 'pending';
                """);
            migrationBuilder.Sql("""
                UPDATE invoices
                SET counter_request = NULL,
                    counter_request_amount = NULL,
                    counter_requested_at = NULL
                WHERE counter_request IS NOT NULL;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Nothing to undo: no schema changed, and which options were on
            // before, or which payments were pending, is not recoverable.
        }
    }
}

namespace DineQR.Api.Services;

/// Every `Payments:Cashfree:ReconcileSeconds`, asks the gateway about
/// pending payments, so a lost or late webhook never leaves a bill waiting
/// and an unpaid order ends when its time runs out.
public sealed class GatewaySweeper(
    IServiceScopeFactory scopes,
    CashfreeOptions options,
    ILogger<GatewaySweeper> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (options.ReconcileSeconds <= 0 || !options.IsConfigured) return;
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(options.ReconcileSeconds));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await using var scope = scopes.CreateAsyncScope();
                var billing = scope.ServiceProvider.GetRequiredService<BillingService>();
                var settled = await billing.SweepGatewayPaymentsAsync(stoppingToken);
                if (settled > 0) logger.LogInformation("Settled {Count} gateway payment(s) by status check", settled);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception error)
            {
                // The next round tries again; never stop the API over it.
                logger.LogError(error, "Gateway payment check failed");
            }
        }
    }
}

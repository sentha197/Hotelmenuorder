START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261118134154_RetireOnlinePayments') THEN
    UPDATE restaurant_settings
    SET online_methods = '{}',
        upi_enabled = false;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261118134154_RetireOnlinePayments') THEN
    UPDATE payments
    SET status = 'cancelled',
        failure_reason = 'Online payment was retired before this was confirmed. Collect the bill at the counter.',
        updated_at = now(),
        confirmed_at = now()
    WHERE status = 'pending';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261118134154_RetireOnlinePayments') THEN
    UPDATE invoices
    SET counter_request = NULL,
        counter_request_amount = NULL,
        counter_requested_at = NULL
    WHERE counter_request IS NOT NULL;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261118134154_RetireOnlinePayments') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261118134154_RetireOnlinePayments', '10.0.13');
    END IF;
END $EF$;
COMMIT;


START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261109090043_SeparateUpiAndQr') THEN
    UPDATE restaurant_settings
    SET online_methods = array_append(online_methods, 'qr')
    WHERE 'upi' = ANY(online_methods) AND NOT ('qr' = ANY(online_methods));
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261109090043_SeparateUpiAndQr') THEN
    UPDATE payments
    SET status = 'failed',
        failure_reason = 'This payment was not completed. No money moved.',
        updated_at = now(),
        confirmed_at = now()
    WHERE provider = 'Simulator' AND status = 'pending';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261109090043_SeparateUpiAndQr') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261109090043_SeparateUpiAndQr', '10.0.13');
    END IF;
END $EF$;
COMMIT;


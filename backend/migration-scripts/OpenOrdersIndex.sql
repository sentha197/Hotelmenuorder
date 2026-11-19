START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261119120839_OpenOrdersIndex') THEN
    CREATE INDEX ix_orders_open_created_at ON orders (created_at) WHERE status <> 'served' AND status <> 'cancelled';
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261119120839_OpenOrdersIndex') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261119120839_OpenOrdersIndex', '10.0.13');
    END IF;
END $EF$;
COMMIT;


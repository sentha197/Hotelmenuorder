START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028181320_StaffCustomAccess') THEN
    ALTER TABLE users ADD COLUMN IF NOT EXISTS custom_permissions character varying(1000) NULL;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028181320_StaffCustomAccess') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261028181320_StaffCustomAccess', '10.0.13');
    END IF;
END $EF$;
COMMIT;

START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028190623_StaffRoleTitle') THEN
    ALTER TABLE users ADD COLUMN IF NOT EXISTS role_title character varying(50) NULL;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261028190623_StaffRoleTitle') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261028190623_StaffRoleTitle', '10.0.13');
    END IF;
END $EF$;
COMMIT;



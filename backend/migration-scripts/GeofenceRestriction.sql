START TRANSACTION;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107195943_GeofenceRestriction') THEN
    CREATE TABLE restaurant_geofences (
        id bigint GENERATED ALWAYS AS IDENTITY,
        settings_id integer NOT NULL,
        latitude double precision NOT NULL,
        longitude double precision NOT NULL,
        radius_meters integer NOT NULL,
        enabled boolean NOT NULL,
        apply_to_takeaway boolean NOT NULL,
        created_at timestamp with time zone NOT NULL,
        updated_at timestamp with time zone NOT NULL,
        updated_by_name character varying(150) NOT NULL,
        CONSTRAINT pk_restaurant_geofences PRIMARY KEY (id),
        CONSTRAINT ck_restaurant_geofences_latitude CHECK (latitude BETWEEN -90 AND 90),
        CONSTRAINT ck_restaurant_geofences_longitude CHECK (longitude BETWEEN -180 AND 180),
        CONSTRAINT ck_restaurant_geofences_radius CHECK (radius_meters BETWEEN 10 AND 1000),
        CONSTRAINT fk_restaurant_geofences_restaurant_settings_settings_id FOREIGN KEY (settings_id) REFERENCES restaurant_settings (id) ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107195943_GeofenceRestriction') THEN
    CREATE UNIQUE INDEX ix_restaurant_geofences_settings_id ON restaurant_geofences (settings_id);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "migration_id" = '20261107195943_GeofenceRestriction') THEN
    INSERT INTO "__EFMigrationsHistory" (migration_id, product_version)
    VALUES ('20261107195943_GeofenceRestriction', '10.0.13');
    END IF;
END $EF$;
COMMIT;


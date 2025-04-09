-- Script SQL ESTÁTICO para configurar replicação lógica no PostgreSQL para Datastream
ALTER USER "datastream_user" WITH REPLICATION;

DROP PUBLICATION IF EXISTS "ds_publication_for_pg_to_bq_stream";
CREATE PUBLICATION "ds_publication_for_pg_to_bq_stream" FOR ALL TABLES;

SELECT PG_CREATE_LOGICAL_REPLICATION_SLOT('ds_replication_slot_for_pg_to_bq_stream', 'pgoutput');

GRANT USAGE ON SCHEMA public TO "datastream_user";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "datastream_user";

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO "datastream_user";

CREATE TABLE IF NOT EXISTS public.maintenance_events (
    event_id SERIAL PRIMARY KEY,
    aircraft_registration VARCHAR(20) NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    description TEXT,
    event_timestamp TIMESTAMPTZ NOT NULL,
    location VARCHAR(100),
    last_updated TIMESTAMPTZ DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.maintenance_events TO "datastream_user";
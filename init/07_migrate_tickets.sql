-- ============================================================
--  BON VOYAGE — Migración de Tickets
--  Crea y normaliza tickets para viajes existentes
--  PostgreSQL 16
-- ============================================================

-- Compatibilidad con esquemas legacy de tickets.
DO $$
BEGIN
    -- Renombra columnas legacy si existen y todavía no se migraron.
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'budget'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'presupuesto_total'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN budget TO presupuesto_total';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_cost'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'costo_acumulado'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN total_cost TO costo_acumulado';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'budget_status'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'estado_presupuesto'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN budget_status TO estado_presupuesto';
    END IF;

    -- Agrega columnas faltantes del esquema actual.
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'presupuesto_total'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN presupuesto_total NUMERIC(12,2)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'costo_acumulado'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN costo_acumulado NUMERIC(12,2)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_lugares'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_lugares INTEGER';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_vuelos'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_vuelos INTEGER';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'estado_presupuesto'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN estado_presupuesto VARCHAR(20)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'balance_disponible'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN balance_disponible NUMERIC(12,2) GENERATED ALWAYS AS (presupuesto_total - costo_acumulado) STORED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_items'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_items INTEGER GENERATED ALWAYS AS (total_lugares + total_vuelos) STORED';
    END IF;
END;
$$;

-- Reemplaza constraints legacy del estado para aceptar solo estados actuales.
DO $$
DECLARE
    v_constraint RECORD;
BEGIN
    FOR v_constraint IN
        SELECT c.conname
        FROM pg_constraint c
        WHERE c.conrelid = 'tickets'::regclass
          AND c.contype = 'c'
          AND pg_get_constraintdef(c.oid) ILIKE '%estado_presupuesto%'
    LOOP
        EXECUTE format('ALTER TABLE tickets DROP CONSTRAINT %I', v_constraint.conname);
    END LOOP;

    ALTER TABLE tickets
        ADD CONSTRAINT chk_tickets_estado_presupuesto
        CHECK (estado_presupuesto IN ('SIN_DATOS', 'EN_RANGO', 'ADVERTENCIA', 'EXCEDIDO'))
        NOT VALID;
EXCEPTION
    WHEN duplicate_object THEN
        NULL;
END;
$$;

-- Refuerza defaults y restricciones numéricas para entornos ya existentes.
ALTER TABLE tickets
    ALTER COLUMN presupuesto_total SET DEFAULT 0,
    ALTER COLUMN costo_acumulado SET DEFAULT 0,
    ALTER COLUMN total_lugares SET DEFAULT 0,
    ALTER COLUMN total_vuelos SET DEFAULT 0;

-- Sanitiza datos legacy que pudieron quedar en NULL.
UPDATE tickets
SET
    presupuesto_total  = COALESCE(presupuesto_total, 0),
    costo_acumulado    = COALESCE(costo_acumulado, 0),
    total_lugares      = COALESCE(total_lugares, 0),
    total_vuelos       = COALESCE(total_vuelos, 0),
    estado_presupuesto = CASE
        WHEN estado_presupuesto = 'WITHIN_BUDGET' THEN 'EN_RANGO'
        WHEN estado_presupuesto = 'OVER_BUDGET'   THEN 'EXCEDIDO'
        WHEN estado_presupuesto IN ('SIN_DATOS', 'EN_RANGO', 'ADVERTENCIA', 'EXCEDIDO')
            THEN estado_presupuesto
        ELSE 'SIN_DATOS'
    END;

ALTER TABLE tickets
    ALTER COLUMN presupuesto_total SET NOT NULL,
    ALTER COLUMN costo_acumulado SET NOT NULL,
    ALTER COLUMN total_lugares SET NOT NULL,
    ALTER COLUMN total_vuelos SET NOT NULL,
    ALTER COLUMN estado_presupuesto SET NOT NULL;

-- Valida el check solo después de normalizar datos legacy.
ALTER TABLE tickets
    VALIDATE CONSTRAINT chk_tickets_estado_presupuesto;

-- Reemplaza índice legacy para alertas en estado actual.
DROP INDEX IF EXISTS idx_tickets_estado_alerta;
CREATE INDEX IF NOT EXISTS idx_tickets_estado_alerta
    ON tickets(estado_presupuesto)
    WHERE estado_presupuesto IN ('ADVERTENCIA', 'EXCEDIDO');

DO $$
DECLARE
    v_trip RECORD;
BEGIN
    FOR v_trip IN
        SELECT trip_id, user_id, COALESCE(total_budget, 0) AS total_budget
        FROM trips
    LOOP
        INSERT INTO tickets (
            trip_id,
            user_id,
            presupuesto_total,
            costo_acumulado,
            total_lugares,
            total_vuelos,
            estado_presupuesto,
            updated_at
        )
        VALUES (
            v_trip.trip_id,
            v_trip.user_id,
            v_trip.total_budget,
            0,
            0,
            0,
            CASE
                WHEN v_trip.total_budget <= 0 THEN 'SIN_DATOS'
                ELSE 'EN_RANGO'
            END,
            NOW()
        )
        ON CONFLICT (trip_id)
        DO UPDATE SET
            user_id            = EXCLUDED.user_id,
            presupuesto_total  = COALESCE(tickets.presupuesto_total, EXCLUDED.presupuesto_total),
            costo_acumulado    = COALESCE(tickets.costo_acumulado, EXCLUDED.costo_acumulado),
            total_lugares      = COALESCE(tickets.total_lugares, EXCLUDED.total_lugares),
            total_vuelos       = COALESCE(tickets.total_vuelos, EXCLUDED.total_vuelos),
            estado_presupuesto = COALESCE(tickets.estado_presupuesto, EXCLUDED.estado_presupuesto),
            updated_at         = NOW();
    END LOOP;
END;
$$;

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
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'presupuesto_total'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_budget'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN presupuesto_total TO total_budget';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'costo_acumulado'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'accumulated_cost'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN costo_acumulado TO accumulated_cost';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'estado_presupuesto'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'budget_status'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN estado_presupuesto TO budget_status';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_lugares'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_places'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN total_lugares TO total_places';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_vuelos'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_flights'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN total_vuelos TO total_flights';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'balance_disponible'
    )
    AND NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'available_balance'
    ) THEN
        EXECUTE 'ALTER TABLE tickets RENAME COLUMN balance_disponible TO available_balance';
    END IF;

    -- Agrega columnas faltantes del esquema actual.
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_budget'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_budget NUMERIC(12,2)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'accumulated_cost'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN accumulated_cost NUMERIC(12,2)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_places'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_places INTEGER';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_flights'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_flights INTEGER';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'budget_status'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN budget_status VARCHAR(20)';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'available_balance'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN available_balance NUMERIC(12,2) GENERATED ALWAYS AS (total_budget - accumulated_cost) STORED';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'tickets' AND column_name = 'total_items'
    ) THEN
        EXECUTE 'ALTER TABLE tickets ADD COLUMN total_items INTEGER GENERATED ALWAYS AS (total_places + total_flights) STORED';
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
          AND pg_get_constraintdef(c.oid) ILIKE '%budget_status%'
    LOOP
        EXECUTE format('ALTER TABLE tickets DROP CONSTRAINT %I', v_constraint.conname);
    END LOOP;

    ALTER TABLE tickets
        ADD CONSTRAINT chk_tickets_budget_status
        CHECK (budget_status IN ('WITHOUT_DATA', 'WITHIN_BUDGET', 'WARNING', 'OVER_BUDGET'))
        NOT VALID;
EXCEPTION
    WHEN duplicate_object THEN
        NULL;
END;
$$;

-- Refuerza defaults y restricciones numéricas para entornos ya existentes.
ALTER TABLE tickets
    ALTER COLUMN total_budget SET DEFAULT 0,
    ALTER COLUMN accumulated_cost SET DEFAULT 0,
    ALTER COLUMN total_places SET DEFAULT 0,
    ALTER COLUMN total_flights SET DEFAULT 0;

-- Sanitiza datos legacy que pudieron quedar en NULL.
UPDATE tickets
SET
    total_budget       = COALESCE(total_budget, 0),
    accumulated_cost   = COALESCE(accumulated_cost, 0),
    total_places       = COALESCE(total_places, 0),
    total_flights      = COALESCE(total_flights, 0),
    budget_status      = CASE
        WHEN budget_status = 'EN_RANGO' THEN 'WITHIN_BUDGET'
        WHEN budget_status = 'EXCEDIDO'   THEN 'OVER_BUDGET'
        WHEN budget_status = 'ADVERTENCIA' THEN 'WARNING'
        WHEN budget_status = 'SIN_DATOS' THEN 'WITHOUT_DATA'
        WHEN budget_status IN ('WITHOUT_DATA', 'WITHIN_BUDGET', 'WARNING', 'OVER_BUDGET')
            THEN budget_status
        ELSE 'WITHOUT_DATA'
    END;

ALTER TABLE tickets
    ALTER COLUMN total_budget SET NOT NULL,
    ALTER COLUMN accumulated_cost SET NOT NULL,
    ALTER COLUMN total_places SET NOT NULL,
    ALTER COLUMN total_flights SET NOT NULL,
    ALTER COLUMN budget_status SET NOT NULL;

-- Valida el check solo después de normalizar datos legacy.
ALTER TABLE tickets
    VALIDATE CONSTRAINT chk_tickets_budget_status;

-- Reemplaza índice legacy para alertas en estado actual.
DROP INDEX IF EXISTS idx_tickets_estado_alerta;
CREATE INDEX IF NOT EXISTS idx_tickets_budget_alert
    ON tickets(budget_status)
    WHERE budget_status IN ('WARNING', 'OVER_BUDGET');

-- Asegura unicidad por viaje para habilitar ON CONFLICT(trip_id).
-- 1) elimina filas huérfanas sin trip_id
DELETE FROM tickets
WHERE trip_id IS NULL;

-- 2) deduplica por trip_id conservando el registro más reciente
WITH ranked AS (
    SELECT
        ctid,
        ROW_NUMBER() OVER (
            PARTITION BY trip_id
            ORDER BY updated_at DESC NULLS LAST,
                     created_at DESC NULLS LAST,
                     ticket_id DESC
        ) AS rn
    FROM tickets
)
DELETE FROM tickets t
USING ranked r
WHERE t.ctid = r.ctid
  AND r.rn > 1;

-- 3) crea índice único si aún no existe
CREATE UNIQUE INDEX IF NOT EXISTS uq_tickets_trip_id
    ON tickets(trip_id);

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
            total_budget,
            accumulated_cost,
            total_places,
            total_flights,
            budget_status,
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
                WHEN v_trip.total_budget <= 0 THEN 'WITHOUT_DATA'
                ELSE 'WITHIN_BUDGET'
            END,
            NOW()
        )
        ON CONFLICT (trip_id)
        DO UPDATE SET
            user_id            = EXCLUDED.user_id,
            total_budget       = COALESCE(tickets.total_budget, EXCLUDED.total_budget),
            accumulated_cost   = COALESCE(tickets.accumulated_cost, EXCLUDED.accumulated_cost),
            total_places       = COALESCE(tickets.total_places, EXCLUDED.total_places),
            total_flights      = COALESCE(tickets.total_flights, EXCLUDED.total_flights),
            budget_status      = COALESCE(tickets.budget_status, EXCLUDED.budget_status),
            updated_at         = NOW();
    END LOOP;
END;
$$;

-- ============================================================
--  BON VOYAGE — Migración de Tickets
--  Crea y normaliza tickets para viajes existentes
--  PostgreSQL 16
-- ============================================================

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
    estado_presupuesto = COALESCE(estado_presupuesto, 'SIN_DATOS');

ALTER TABLE tickets
    ALTER COLUMN presupuesto_total SET NOT NULL,
    ALTER COLUMN costo_acumulado SET NOT NULL,
    ALTER COLUMN total_lugares SET NOT NULL,
    ALTER COLUMN total_vuelos SET NOT NULL,
    ALTER COLUMN estado_presupuesto SET NOT NULL;

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

-- ============================================================
--  BON VOYAGE — Recalculate All Tickets
--  Re-populate ticket item counts and financial summaries
--  PostgreSQL 16
-- ============================================================

-- Recalculates all existing tickets to populate the item counts
-- that were created as 0 during initial migration.
-- Calls fn_recalculate_ticket for each trip with a ticket.

DO $$
DECLARE
    v_trip_id UUID;
    v_count INTEGER := 0;
BEGIN
    FOR v_trip_id IN
        SELECT trip_id
        FROM tickets
        WHERE trip_id IS NOT NULL
        ORDER BY created_at ASC
    LOOP
        PERFORM fn_recalculate_ticket(v_trip_id);
        v_count := v_count + 1;
    END LOOP;

    RAISE NOTICE 'Tickets recalculados: %', v_count;
END;
$$;

-- Validación: mostrar tickets con conteos poblados
SELECT 
    trip_id,
    user_id,
    total_budget,
    accumulated_cost,
    available_balance,
    total_places,
    total_flights,
    total_items,
    budget_status,
    updated_at
FROM tickets
ORDER BY updated_at DESC
LIMIT 10;

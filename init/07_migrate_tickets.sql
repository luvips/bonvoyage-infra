-- ============================================================
--  BON VOYAGE — Migración de Tickets
--  Crea tickets para viajes ya existentes en la plataforma
--  PostgreSQL 16
-- ============================================================

DO $$
DECLARE
    v_trip RECORD;
    v_ticket_count INTEGER;
BEGIN
    FOR v_trip IN SELECT trip_id, user_id, total_budget, currency FROM trips
    LOOP
        -- Revisa si ya existe un ticket generado para este viaje
        SELECT count(*) INTO v_ticket_count FROM tickets WHERE trip_id = v_trip.trip_id;
        
        -- Inserta un nuevo ticket únicamente si el recuento es cero
        IF v_ticket_count = 0 THEN
            INSERT INTO tickets (trip_id, user_id, budget, currency)
            VALUES (
                v_trip.trip_id, 
                v_trip.user_id, 
                v_trip.total_budget, 
                COALESCE(v_trip.currency, 'USD')
            );
        END IF;
    END LOOP;
END;
$$;

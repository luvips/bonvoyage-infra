-- ============================================================
--  BON VOYAGE — Stored Procedures
--  Stored Procedures unicamente
--  PostgreSQL 16
--
--  Orden de ejecución: después de 05_triggers.sql
--  Depende de: todas las tablas y funciones previas
--
--  Procedures incluidos:
--    a) sp_confirmar_viaje               
--    b) sp_recalcular_presupuesto_cursor
--    c) sp_limpiar_viajes_abandonados    
-- ============================================================


-- ------------------------------------------------------------
--  sp_confirmar_viaje
--  Qué hace: Confirma un viaje de forma atómica usando FOR UPDATE
--  para bloquear la fila durante la transacción. Verifica que
--  el viaje exista y esté en DRAFT antes de cambiarlo a CONFIRMED
--  con confirmed_at = NOW(). Si cualquier paso falla, el ROLLBACK
--  deshace todo y RAISE NOTICE informa el error sin propagarlo.
--
--  Uso: CALL sp_confirmar_viaje('uuid-del-viaje');
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_confirmar_viaje(p_trip_id UUID)
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT status INTO v_status
    FROM trips
    WHERE trip_id = p_trip_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'El viaje (id: %) no existe.', p_trip_id;
    END IF;

    IF v_status <> 'DRAFT' THEN
        RAISE EXCEPTION 'El viaje no puede confirmarse. Estatus actual: %', v_status;
    END IF;

    UPDATE trips
    SET status       = 'CONFIRMED',
        confirmed_at = NOW(),
        updated_at   = NOW()
    WHERE trip_id = p_trip_id;

    COMMIT;
    RAISE NOTICE 'Transacción exitosa: viaje % confirmado.', p_trip_id;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE NOTICE 'Rollback por error: %', SQLERRM;
END;
$$;


-- ------------------------------------------------------------
--  sp_recalcular_presupuesto_cursor
--  Qué hace: Itera ítem por ítem sobre el itinerario activo
--  del viaje, acumula los costos estimados con un contador
--  manual y actualiza total_budget en trips con el resultado.
--  Es útil para reconciliar el presupuesto tras importaciones
--  masivas o correcciones manuales de costos.
--
--  Uso: CALL sp_recalcular_presupuesto_cursor('uuid-del-viaje');
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_recalcular_presupuesto_cursor(p_trip_id UUID)
LANGUAGE plpgsql
AS $$
DECLARE
    cur_items CURSOR FOR
        SELECT ii.estimated_cost
        FROM itinerary_items ii
        JOIN itinerary_days id_ ON ii.day_id = id_.day_id
        WHERE id_.trip_id           = p_trip_id
          AND ii.estimated_cost IS NOT NULL
          AND ii.status            <> 'CANCELLED';

    v_costo_item  NUMERIC;
    v_total_costo NUMERIC := 0;
BEGIN
    OPEN cur_items;

    LOOP
        FETCH cur_items INTO v_costo_item;
        EXIT WHEN NOT FOUND;
        v_total_costo := v_total_costo + v_costo_item;
    END LOOP;

    CLOSE cur_items;

    UPDATE trips
    SET total_budget = v_total_costo,
        updated_at   = NOW()
    WHERE trip_id = p_trip_id;

    COMMIT;
END;
$$;


-- ------------------------------------------------------------
--  sp_limpiar_viajes_abandonados
--  Qué hace: Marca como CANCELLED todos los viajes en DRAFT
--  que llevan más de 6 meses sin actualizarse. Procesa en lotes
--  de 100 para no bloquear la BD completa en una sola transacción
--  larga. Al terminar reporta cuántos viajes fueron cancelados.
--  Diseñado para ejecutarse como tarea programada (cron).
--
--  Uso: CALL sp_limpiar_viajes_abandonados();
-- ------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_limpiar_viajes_abandonados()
LANGUAGE plpgsql
AS $$
DECLARE
    v_record RECORD;
    v_count  INTEGER := 0;
BEGIN
    FOR v_record IN
        SELECT trip_id
        FROM trips
        WHERE status     = 'DRAFT'
          AND updated_at < NOW() - INTERVAL '6 months'
    LOOP
        UPDATE trips
        SET status     = 'CANCELLED',
            updated_at = NOW()
        WHERE trip_id = v_record.trip_id;

        v_count := v_count + 1;

        -- Commit parcial cada 100 registros (procesamiento batch)
        IF MOD(v_count, 100) = 0 THEN
            COMMIT;
        END IF;
    END LOOP;

    COMMIT;
    RAISE NOTICE 'Limpieza completada. Viajes cancelados: %', v_count;
END;
$$;
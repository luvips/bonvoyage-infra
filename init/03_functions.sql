-- ============================================================
--  BON VOYAGE — Funciones
--  Funciones unicamente
--  PostgreSQL 16 
--
--  Orden de ejecución: después de 03_views.sql
--  Depende de: todas las tablas del schema
--
--  Funciones incluidas:
--    a) fn_calcular_horas_planificacion  
--    b) fn_obtener_resumen_viajes        
--    c) fn_create_trip                  
--    d) fn_change_trip_status           
--    e) fn_delete_trip                   
--    f) fn_add_itinerary_item            
--    g) fn_reorder_day_items             
--    h) fn_recalcular_ticket           
-- ============================================================


-- ------------------------------------------------------------
--  fn_calcular_horas_planificacion
--  Tipo: Escalar — retorna NUMERIC
--  Usada en: vw_hipotesis_validacion
--  Convierte segundos de planificación a horas con 2 decimales.
--  No contiene COMMIT ni ROLLBACK (prohibido en funciones).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calcular_horas_planificacion(p_segundos INTEGER)
RETURNS NUMERIC
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN ROUND(COALESCE(p_segundos, 0)::NUMERIC / 3600.0, 2);
END;
$$;


-- ------------------------------------------------------------
--  fn_obtener_resumen_viajes
--  Tipo: Tabulada — retorna TABLE
--  Retorna los viajes activos de un usuario listos para
--  consumir desde el backend sin múltiples queries.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_obtener_resumen_viajes(p_user_id UUID)
RETURNS TABLE (
    trip_id      UUID,
    trip_name    VARCHAR,
    start_date   DATE,
    end_date     DATE,
    status       VARCHAR,
    total_budget NUMERIC,
    total_days   INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.trip_id,
        t.trip_name,
        t.start_date,
        t.end_date,
        t.status,
        t.total_budget,
        (t.end_date - t.start_date + 1)::INTEGER AS total_days
    FROM trips t
    WHERE t.user_id = p_user_id
      AND t.status <> 'CANCELLED'
    ORDER BY t.start_date DESC;
END;
$$;


-- ------------------------------------------------------------
--  fn_create_trip
--  Tipo: Lógica de negocio — retorna UUID
--  Crea el viaje, genera un itinerary_day por cada fecha del
--  rango y agenda el correo de recordatorio a 23 días.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_create_trip(
    p_user_id        UUID,
    p_trip_name      VARCHAR(255),
    p_destination_id UUID,
    p_start_date     DATE,
    p_end_date       DATE,
    p_total_budget   NUMERIC(12,2) DEFAULT NULL,
    p_currency       VARCHAR(10)   DEFAULT 'USD'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip_id  UUID;
    v_day_date DATE;
    v_day_num  SMALLINT := 1;
BEGIN
    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date must be >= start_date';
    END IF;

    IF (p_end_date - p_start_date) > 30 THEN
        RAISE EXCEPTION 'Trip cannot exceed 30 days';
    END IF;

    INSERT INTO trips (
        user_id, destination_id, trip_name,
        start_date, end_date, total_budget, currency, status
    )
    VALUES (
        p_user_id, p_destination_id, p_trip_name,
        p_start_date, p_end_date, p_total_budget, p_currency, 'DRAFT'
    )
    RETURNING trip_id INTO v_trip_id;

    -- Generar un día por cada fecha del rango
    v_day_date := p_start_date;
    WHILE v_day_date <= p_end_date LOOP
        INSERT INTO itinerary_days (trip_id, day_date, day_number)
        VALUES (v_trip_id, v_day_date, v_day_num);

        v_day_date := v_day_date + INTERVAL '1 day';
        v_day_num  := v_day_num  + 1;
    END LOOP;

    -- Agendar recordatorio de borrador a 23 días
    INSERT INTO email_notifications (
        user_id, notification_type, template_data,
        status, scheduled_for, related_entity_type, related_entity_id
    )
    VALUES (
        p_user_id, 'DRAFT_REMINDER',
        jsonb_build_object('trip_id', v_trip_id, 'trip_name', p_trip_name),
        'PENDING', NOW() + INTERVAL '23 days',
        'TRIP', v_trip_id
    );

    RETURN v_trip_id;
END;
$$;


-- ------------------------------------------------------------
--  fn_change_trip_status
--  Tipo: Máquina de estados — retorna VARCHAR(20)
--  Valida transiciones permitidas entre estados del viaje,
--  cancela notificaciones anteriores, crea las nuevas según
--  el estado resultante y registra en user_travel_history
--  al completar un viaje.
--  Transiciones válidas:
--    DRAFT      → CONFIRMED  (acción: CONFIRM)
--    DRAFT      → CANCELLED  (acción: CANCEL)
--    CONFIRMED  → CANCELLED  (acción: CANCEL)
--    CONFIRMED  → COMPLETED  (acción: COMPLETE)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_change_trip_status(UUID, UUID, VARCHAR);

CREATE OR REPLACE FUNCTION fn_change_trip_status(
    p_trip_id UUID,
    p_user_id UUID,
    p_action  VARCHAR(20)
)
RETURNS VARCHAR(20)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(20);
    v_new_status     VARCHAR(20);
    v_trip_name      VARCHAR(255);
    v_destination    VARCHAR(255);
    v_country        VARCHAR(100);
    v_start_date     DATE;
    v_end_date       DATE;
BEGIN
    SELECT t.status, t.trip_name, t.start_date, t.end_date,
           COALESCE(d.name, 'Destino'), COALESCE(d.country, '')
    INTO   v_current_status, v_trip_name, v_start_date, v_end_date,
           v_destination, v_country
    FROM trips t
    LEFT JOIN destinations d ON d.destination_id = t.destination_id
    WHERE t.trip_id = p_trip_id
      AND t.user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip not found or access denied';
    END IF;

    CASE p_action
        WHEN 'CONFIRM' THEN
            IF v_current_status <> 'DRAFT' THEN
                RAISE EXCEPTION 'Only DRAFT trips can be confirmed';
            END IF;
            v_new_status := 'CONFIRMED';

        WHEN 'CANCEL' THEN
            IF v_current_status NOT IN ('DRAFT', 'CONFIRMED') THEN
                RAISE EXCEPTION 'Only DRAFT or CONFIRMED trips can be cancelled';
            END IF;
            v_new_status := 'CANCELLED';

        WHEN 'COMPLETE' THEN
            IF v_current_status <> 'CONFIRMED' THEN
                RAISE EXCEPTION 'Only CONFIRMED trips can be completed';
            END IF;
            IF v_end_date > CURRENT_DATE THEN
                RAISE EXCEPTION 'Trip end_date has not passed yet';
            END IF;
            v_new_status := 'COMPLETED';

        ELSE
            RAISE EXCEPTION 'Invalid action: %. Use CONFIRM, CANCEL or COMPLETE', p_action;
    END CASE;

    UPDATE trips
    SET status       = v_new_status,
        confirmed_at = CASE WHEN v_new_status = 'CONFIRMED' THEN NOW() ELSE confirmed_at END,
        updated_at   = NOW()
    WHERE trip_id = p_trip_id;

    -- Cancelar notificaciones pendientes previas del viaje
    UPDATE email_notifications
    SET status = 'CANCELLED'
    WHERE related_entity_id   = p_trip_id
      AND related_entity_type = 'TRIP'
      AND status              = 'PENDING';

    IF v_new_status = 'CONFIRMED' THEN

        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for, related_entity_type, related_entity_id
        )
        VALUES (
            p_user_id, 'TRIP_CONFIRMED',
            jsonb_build_object('trip_name', v_trip_name, 'start_date', v_start_date),
            'PENDING', NOW(), 'TRIP', p_trip_id
        );

        -- Recordatorios a 30, 7 y 1 día antes del viaje
        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for, related_entity_type, related_entity_id
        )
        SELECT
            p_user_id,
            'TRIP_UPCOMING',
            jsonb_build_object(
                'trip_name',  v_trip_name,
                'days_until', days_before,
                'start_date', v_start_date
            ),
            'PENDING',
            v_start_date - (days_before || ' days')::INTERVAL,
            'TRIP',
            p_trip_id
        FROM unnest(ARRAY[30, 7, 1]) AS days_before
        WHERE v_start_date - (days_before || ' days')::INTERVAL > NOW();

    ELSIF v_new_status = 'COMPLETED' THEN

        INSERT INTO user_travel_history (
            user_id, trip_id, destination, country, travel_date
        )
        VALUES (
            p_user_id, p_trip_id, v_destination, v_country, v_start_date
        );

    END IF;

    RETURN v_new_status;
END;
$$;


-- ------------------------------------------------------------
--  fn_delete_trip
--  Tipo: Cascade manual — retorna BOOLEAN
--  de eliminación en cascada. Solo permite borrar viajes en
--  estado DRAFT o CANCELLED. Cancela notificaciones pendientes
--  y elimina en orden: ítems → trip_tags → días → ticket → viaje.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_delete_trip(
    p_trip_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_status VARCHAR(20);
BEGIN
    SELECT status INTO v_status
    FROM trips
    WHERE trip_id = p_trip_id
      AND user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip not found or access denied';
    END IF;

    IF v_status NOT IN ('DRAFT', 'CANCELLED') THEN
        RAISE EXCEPTION 'Only DRAFT or CANCELLED trips can be deleted. Current status: %', v_status;
    END IF;

    UPDATE email_notifications
    SET status = 'CANCELLED'
    WHERE related_entity_id   = p_trip_id
      AND related_entity_type = 'TRIP'
      AND status              = 'PENDING';

    DELETE FROM itinerary_items
    WHERE day_id IN (
        SELECT day_id FROM itinerary_days WHERE trip_id = p_trip_id
    );

    DELETE FROM trip_tags      WHERE trip_id = p_trip_id;
    DELETE FROM itinerary_days WHERE trip_id = p_trip_id;
    DELETE FROM tickets        WHERE trip_id = p_trip_id;
    DELETE FROM trips          WHERE trip_id = p_trip_id;

    RETURN TRUE;
END;
$$;


-- ------------------------------------------------------------
--  fn_add_itinerary_item
--  Tipo: Lógica de negocio — retorna UUID
--  Agrega un lugar o vuelo al itinerario. Para vuelos, resuelve
--  automáticamente el día correcto según departure_time.
--  Calcula la siguiente posición con MAX(order_position)+1.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_add_itinerary_item(
    p_trip_id        UUID,
    p_day_id         UUID,
    p_item_type      VARCHAR(20),
    p_place_ref_id   UUID          DEFAULT NULL,
    p_flight_ref_id  UUID          DEFAULT NULL,
    p_start_time     TIME          DEFAULT NULL,
    p_end_time       TIME          DEFAULT NULL,
    p_estimated_cost NUMERIC(10,2) DEFAULT NULL,
    p_notes          TEXT          DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_item_id       UUID;
    v_target_day_id UUID;
    v_next_position SMALLINT;
    v_flight_date   DATE;
BEGIN
    IF p_item_type = 'PLACE' AND p_place_ref_id IS NULL THEN
        RAISE EXCEPTION 'place_reference_id is required for PLACE items';
    END IF;

    IF p_item_type = 'FLIGHT' AND p_flight_ref_id IS NULL THEN
        RAISE EXCEPTION 'flight_reference_id is required for FLIGHT items';
    END IF;

    IF p_item_type = 'FLIGHT' THEN
        SELECT departure_time::DATE INTO v_flight_date
        FROM flight_references
        WHERE reference_id = p_flight_ref_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'flight_reference not found: %', p_flight_ref_id;
        END IF;

        SELECT day_id INTO v_target_day_id
        FROM itinerary_days
        WHERE trip_id  = p_trip_id
          AND day_date = v_flight_date;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'No itinerary day found for flight date %', v_flight_date;
        END IF;
    ELSE
        v_target_day_id := p_day_id;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM itinerary_days
        WHERE day_id  = v_target_day_id
          AND trip_id = p_trip_id
    ) THEN
        RAISE EXCEPTION 'day_id % does not belong to trip %', v_target_day_id, p_trip_id;
    END IF;

    SELECT COALESCE(MAX(order_position), 0) + 1
    INTO   v_next_position
    FROM   itinerary_items
    WHERE  day_id = v_target_day_id;

    INSERT INTO itinerary_items (
        day_id, item_type,
        place_reference_id, flight_reference_id,
        order_position, start_time, end_time,
        estimated_cost, notes, status
    )
    VALUES (
        v_target_day_id, p_item_type,
        p_place_ref_id, p_flight_ref_id,
        v_next_position, p_start_time, p_end_time,
        p_estimated_cost, p_notes, 'PLANNED'
    )
    RETURNING item_id INTO v_item_id;

    RETURN v_item_id;
END;
$$;


-- ------------------------------------------------------------
--  fn_reorder_day_items
--  Tipo: Utilitaria — retorna VOID
--  Renumera consecutivamente los ítems no cancelados de un día.
--  Evita huecos como (1, 3, 4) tras borrar un ítem intermedio.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reorder_day_items(p_day_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    WITH ranked AS (
        SELECT item_id,
               ROW_NUMBER() OVER (ORDER BY order_position, created_at) AS new_pos
        FROM itinerary_items
        WHERE day_id = p_day_id
          AND status <> 'CANCELLED'
    )
    UPDATE itinerary_items ii
    SET    order_position = r.new_pos
    FROM   ranked r
    WHERE  ii.item_id = r.item_id;
END;
$$;


-- ------------------------------------------------------------
--  fn_recalculate_ticket
--  Tipo: Automatización de tickets — retorna VOID
--  Llamada exclusivamente por los triggers de tickets.
--  Suma costos y cuenta ítems activos del itinerario, obtiene
--  el presupuesto del viaje, calcula el estado del balance y
--  hace UPSERT en tickets (crea si no existe, actualiza si sí).
--  Estados posibles del presupuesto:
--    WITHOUT_DATA — presupuesto no definido (total_budget = 0)
--    WITHIN_BUDGET — costo acumulado <= 80% del presupuesto
--    WARNING — costo acumulado entre 80% y 100%
--    OVER_BUDGET — costo acumulado > presupuesto
--  NOTA: Equipo backend debe asegurar que esta función actualice
--        total_places, total_flights, y total_items cuando se 
--        insertan, actualizan o eliminan items del itinerario.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_recalculate_ticket(p_trip_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id            UUID;
    v_total_budget       NUMERIC(12,2);
    v_accumulated_cost   NUMERIC(12,2);
    v_total_places       INTEGER;
    v_total_flights      INTEGER;
    v_status             VARCHAR(20);
    v_percentage         NUMERIC(5,2);
BEGIN
    SELECT user_id, COALESCE(total_budget, 0)
    INTO   v_user_id, v_total_budget
    FROM   trips
    WHERE  trip_id = p_trip_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    SELECT
        COALESCE(SUM(ii.estimated_cost), 0),
        COUNT(*) FILTER (WHERE ii.item_type = 'PLACE'),
        COUNT(*) FILTER (WHERE ii.item_type = 'FLIGHT')
    INTO
        v_accumulated_cost,
        v_total_places,
        v_total_flights
    FROM itinerary_items ii
    JOIN itinerary_days  id_ ON id_.day_id = ii.day_id
    WHERE id_.trip_id = p_trip_id
      AND ii.status  <> 'CANCELLED';

    IF v_total_budget <= 0 THEN
        v_status := 'WITHOUT_DATA';
    ELSE
        v_percentage := (v_accumulated_cost / v_total_budget) * 100;
        v_status := CASE
            WHEN v_percentage > 100 THEN 'OVER_BUDGET'
            WHEN v_percentage > 80  THEN 'WARNING'
            ELSE                        'WITHIN_BUDGET'
        END;
    END IF;

    UPDATE tickets
    SET
        user_id            = v_user_id,
        total_budget       = COALESCE(v_total_budget, 0),
        accumulated_cost   = COALESCE(v_accumulated_cost, 0),
        total_places       = COALESCE(v_total_places, 0),
        total_flights      = COALESCE(v_total_flights, 0),
        budget_status      = v_status,
        updated_at         = NOW()
    WHERE trip_id = p_trip_id;

    IF NOT FOUND THEN
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
            p_trip_id,
            v_user_id,
            COALESCE(v_total_budget, 0),
            COALESCE(v_accumulated_cost, 0),
            COALESCE(v_total_places, 0),
            COALESCE(v_total_flights, 0),
            v_status,
            NOW()
        );
    END IF;
END;
$$;
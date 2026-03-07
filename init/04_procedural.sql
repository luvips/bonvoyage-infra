-- ============================================================

-- ============================================================
--  TRIGGER 1: Actualizar trips.updated_at
--  Se dispara al insertar, modificar o eliminar un itinerary_item
-- ============================================================

CREATE OR REPLACE FUNCTION fn_update_trip_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_trip_id UUID;
BEGIN
    SELECT trip_id INTO v_trip_id
    FROM itinerary_days
    WHERE day_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.day_id ELSE NEW.day_id END;

    UPDATE trips
    SET updated_at = NOW()
    WHERE trip_id = v_trip_id;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_items_update_trip_timestamp
AFTER INSERT OR UPDATE OR DELETE ON itinerary_items
FOR EACH ROW EXECUTE FUNCTION fn_update_trip_timestamp();


-- ============================================================
--  TRIGGER 2: Actualizar users.updated_at automáticamente
-- ============================================================

CREATE OR REPLACE FUNCTION fn_update_user_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION fn_update_user_timestamp();


-- ============================================================
--  FUNCTION 1: Crear viaje + generar días automáticamente
--  Retorna: UUID del viaje creado
--
--  Uso:
--  SELECT fn_create_trip(
--    'user_uuid', 'Mi viaje', 'dest_uuid',
--    '2025-06-01', '2025-06-07', 2000.00, 'USD'
--  );
-- ============================================================

CREATE OR REPLACE FUNCTION fn_create_trip(
    p_user_id        UUID,
    p_trip_name      VARCHAR(255),
    p_destination_id UUID,
    p_start_date     DATE,
    p_end_date       DATE,
    p_total_budget   DECIMAL(12,2) DEFAULT NULL,
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

    v_day_date := p_start_date;
    WHILE v_day_date <= p_end_date LOOP
        INSERT INTO itinerary_days (trip_id, day_date, day_number)
        VALUES (v_trip_id, v_day_date, v_day_num);

        v_day_date := v_day_date + INTERVAL '1 day';
        v_day_num  := v_day_num  + 1;
    END LOOP;

    INSERT INTO email_notifications (
        user_id, notification_type, template_data,
        status, scheduled_for,
        related_entity_type, related_entity_id
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


-- ============================================================
--  FUNCTION 2: Cambiar status del viaje + acciones derivadas
--  Retorna: nuevo status aplicado
--
--  Uso:
--  SELECT fn_change_trip_status('trip_uuid', 'user_uuid', 'CONFIRM');
--  SELECT fn_change_trip_status('trip_uuid', 'user_uuid', 'CANCEL');
--  SELECT fn_change_trip_status('trip_uuid', 'user_uuid', 'COMPLETE');
-- ============================================================

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

    UPDATE email_notifications
    SET status = 'CANCELLED'
    WHERE related_entity_id   = p_trip_id
      AND related_entity_type = 'TRIP'
      AND status              = 'PENDING';

    IF v_new_status = 'CONFIRMED' THEN

        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for,
            related_entity_type, related_entity_id
        )
        VALUES (
            p_user_id, 'TRIP_CONFIRMED',
            jsonb_build_object('trip_name', v_trip_name, 'start_date', v_start_date),
            'PENDING', NOW(),
            'TRIP', p_trip_id
        );

        INSERT INTO email_notifications (
            user_id, notification_type, template_data,
            status, scheduled_for,
            related_entity_type, related_entity_id
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


-- ============================================================
--  FUNCTION 3: Eliminar viaje con cascade manual
--  Retorna: TRUE si se eliminó correctamente
--
--  Uso:
--  SELECT fn_delete_trip('trip_uuid', 'user_uuid');
-- ============================================================

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

    DELETE FROM itinerary_days WHERE trip_id = p_trip_id;
    DELETE FROM trips          WHERE trip_id = p_trip_id;

    RETURN TRUE;
END;
$$;


-- ============================================================
--  FUNCTION 4: Agregar ítem + auto-asignar vuelo al día por fecha
--  Retorna: UUID del ítem creado
--
--  Uso (lugar):
--  SELECT fn_add_itinerary_item(
--    'trip_uuid', 'day_uuid', 'PLACE', 'place_ref_uuid', NULL, ...
--  );
--
--  Uso (vuelo — day_id se ignora, se calcula por departure_time):
--  SELECT fn_add_itinerary_item(
--    'trip_uuid', NULL, 'FLIGHT', NULL, 'flight_ref_uuid', ...
--  );
-- ============================================================

CREATE OR REPLACE FUNCTION fn_add_itinerary_item(
    p_trip_id        UUID,
    p_day_id         UUID,
    p_item_type      VARCHAR(20),
    p_place_ref_id   UUID          DEFAULT NULL,
    p_flight_ref_id  UUID          DEFAULT NULL,
    p_start_time     TIME          DEFAULT NULL,
    p_end_time       TIME          DEFAULT NULL,
    p_estimated_cost DECIMAL(10,2) DEFAULT NULL,
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
        WHERE day_id = v_target_day_id
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


-- ============================================================
--  FUNCTION 5: Recalcular order_position de un día
--  Llamar después de eliminar un ítem para mantener consecutividad
--
--  Uso:
--  SELECT fn_reorder_day_items('day_uuid');
-- ============================================================

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
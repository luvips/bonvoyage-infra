-- ============================================================
--  BON VOYAGE — Triggers
--  Triggers unicamente
--  PostgreSQL 16 
--
--  Orden de ejecución: después de 04_functions.sql
--  Depende de: fn_recalculate_ticket (03_functions.sql)
--
--  Triggers incluidos:
--    a) trg_users_updated_at            — auditoría updated_at en users
--    b) trg_items_update_trip_timestamp — auditoría updated_at en trips
--    c) trg_validar_fechas_viaje        — validación de negocio en trips
--    d) trg_ticket_por_items            — automatización ticket 
--    e) trg_ticket_por_presupuesto      — automatización ticket 
-- ============================================================


-- ------------------------------------------------------------
--  TRIGGER A: Auditoría de updated_at en users
--
--  fn_update_user_timestamp / trg_users_updated_at
--  Qué hace: Intercepta cualquier UPDATE en users y fuerza
--  updated_at = NOW() antes de persistir el cambio, sin que
--  el backend tenga que enviarlo explícitamente.
--  Tipo: BEFORE UPDATE — modifica NEW antes de escribir.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_update_user_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_users_updated_at ON users;
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION fn_update_user_timestamp();


-- ------------------------------------------------------------
--  TRIGGER B: Auditoría de updated_at en trips (cascada)
--
--  fn_update_trip_timestamp / trg_items_update_trip_timestamp
--  Qué hace: Cuando se inserta, modifica o elimina un ítem del
--  itinerario, actualiza el updated_at del viaje "padre" para
--  reflejar que su contenido cambió.
--  Navega: itinerary_items → itinerary_days → trips.
--  Usa OLD.day_id en DELETE y NEW.day_id en INSERT/UPDATE.
--  Tipo: AFTER INSERT OR UPDATE OR DELETE.
-- ------------------------------------------------------------
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

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_items_update_trip_timestamp ON itinerary_items;
CREATE TRIGGER trg_items_update_trip_timestamp
AFTER INSERT OR UPDATE OR DELETE ON itinerary_items
FOR EACH ROW EXECUTE FUNCTION fn_update_trip_timestamp();


-- ------------------------------------------------------------
--  TRIGGER C: Validación de fechas en trips
--
--  fn_trg_validar_fechas_viaje / trg_validar_fechas_viaje
--  Qué hace: Antes de insertar o actualizar un viaje, valida
--  que end_date >= start_date y que el viaje no supere 30 días.
--  Si alguna condición falla lanza RAISE EXCEPTION y aborta
--  toda la operación.
--  Tipo: BEFORE INSERT OR UPDATE.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_validar_fechas_viaje()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.end_date < NEW.start_date THEN
        RAISE EXCEPTION 'Violación lógica: end_date no puede ser anterior a start_date.';
    END IF;

    IF (NEW.end_date - NEW.start_date) > 30 THEN
        RAISE EXCEPTION 'Límite de tiempo: un viaje no puede superar 30 días.';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_fechas_viaje ON trips;
CREATE TRIGGER trg_validar_fechas_viaje
BEFORE INSERT OR UPDATE ON trips
FOR EACH ROW EXECUTE FUNCTION fn_trg_validar_fechas_viaje();


-- ------------------------------------------------------------
--  TRIGGER D: Automatización de tickets — por ítems
--
--  fn_trg_ticket_por_items / trg_ticket_por_items
--  Qué hace: Se dispara cuando alguien agrega un ítem (INSERT),
--  lo elimina (DELETE) o modifica su costo o estado (UPDATE OF).
--  Obtiene el trip_id navegando itinerary_items → itinerary_days
--  y llama a fn_recalculate_ticket para actualizar el ticket.
--  El UPDATE OF limita el disparo solo a cambios en las columnas
--  estimated_cost, status, item_type y day_id, evitando disparos
--  innecesarios y cubriendo movimientos de ítems entre días.
--  Casos cubiertos:
--    1 — alguien agrega un lugar o vuelo al itinerario
--    2 — alguien elimina algo de su itinerario
--    3 — alguien modifica el costo estimado de un ítem
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_ticket_por_items()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_new_trip_id UUID;
    v_old_trip_id UUID;
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        SELECT trip_id INTO v_new_trip_id
        FROM itinerary_days
        WHERE day_id = NEW.day_id;
    END IF;

    IF TG_OP IN ('DELETE', 'UPDATE') THEN
        SELECT trip_id INTO v_old_trip_id
        FROM itinerary_days
        WHERE day_id = OLD.day_id;
    END IF;

    IF v_new_trip_id IS NOT NULL THEN
        PERFORM fn_recalculate_ticket(v_new_trip_id);
    END IF;

    IF v_old_trip_id IS NOT NULL
       AND (v_new_trip_id IS NULL OR v_old_trip_id <> v_new_trip_id) THEN
        PERFORM fn_recalculate_ticket(v_old_trip_id);
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_por_items ON itinerary_items;
CREATE TRIGGER trg_ticket_por_items
AFTER INSERT OR DELETE OR UPDATE OF estimated_cost, status, item_type, day_id
ON itinerary_items
FOR EACH ROW EXECUTE FUNCTION fn_trg_ticket_por_items();


-- ------------------------------------------------------------
--  TRIGGER E: Automatización de tickets — por presupuesto
--
--  fn_trg_ticket_por_presupuesto / trg_ticket_por_presupuesto
--  Qué hace: Se dispara cuando alguien ajusta total_budget en
--  trips desde la pantalla de detalle del viaje en el frontend.
--  Recalcula el estado del ticket con el nuevo presupuesto y
--  determina si el viaje pasa a WITHIN_BUDGET, WARNING u OVER_BUDGET.
--  El UPDATE OF limita el disparo a cambios solo en total_budget,
--  sin dispararse por cambios de nombre, status u otros campos.
--  Caso cubierto:
--    4 — alguien ajusta el presupuesto total del viaje
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trg_ticket_por_presupuesto()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM fn_recalculate_ticket(NEW.trip_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ticket_por_presupuesto ON trips;
CREATE TRIGGER trg_ticket_por_presupuesto
AFTER UPDATE OF total_budget
ON trips
FOR EACH ROW EXECUTE FUNCTION fn_trg_ticket_por_presupuesto();
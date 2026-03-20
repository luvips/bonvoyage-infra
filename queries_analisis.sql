-- ============================================================
--  BON VOYAGE — Queries
--  Consultas de Análisis
--  PostgreSQL 16
-- ============================================================

-- ------------------------------------------------------------
--  Query 1: Resultado de la hipótesis por usuario
--  Directamente vinculado a la métrica de la hipótesis.
--  Qué mide: cuántos viajes validaron o invalidaron el objetivo
--  de planificación < 2.5 horas, con el promedio real de horas.
--  Técnicas: SELECT sobre vw_hipotesis_validacion, COUNT, AVG,
--  GROUP BY sobre el campo calculado resultado_hipotesis.
-- ------------------------------------------------------------
SELECT
    resultado_hipotesis,
    COUNT(trip_id)             AS total_viajes,
    AVG(horas_planificacion)   AS promedio_horas,
    MIN(horas_planificacion)   AS minimo_horas,
    MAX(horas_planificacion)   AS maximo_horas
FROM vw_hipotesis_validacion
GROUP BY resultado_hipotesis
ORDER BY total_viajes DESC;


-- ------------------------------------------------------------
--  Query 2: Usuarios con correos fallidos (CTE)
--  Qué mide: qué usuarios tuvieron notificaciones fallidas
--  durante la fase de datos reales, para detectar correos
--  inválidos o problemas del proveedor Brevo.
--  Técnicas: CTE (WITH FallasCorreoCTE AS ...), JOIN entre
--  CTE y users, COALESCE, COUNT, HAVING, ORDER BY.
-- ------------------------------------------------------------
WITH FallasCorreoCTE AS (
    SELECT
        user_id,
        COALESCE(subject, 'Sin asunto') AS asunto_resuelto,
        notification_type,
        status
    FROM email_notifications
    WHERE status = 'FAILED'
)
SELECT
    u.first_name || ' ' || u.last_name  AS usuario_afectado,
    u.email,
    fc.asunto_resuelto,
    fc.notification_type,
    COUNT(*)                            AS total_fallos
FROM FallasCorreoCTE fc
JOIN users u ON u.user_id = fc.user_id
GROUP BY u.first_name, u.last_name, u.email,
         fc.asunto_resuelto, fc.notification_type
HAVING COUNT(*) >= 1
ORDER BY total_fallos DESC;


-- ------------------------------------------------------------
--  Query 3: Segmentación de usuarios por inversión en viajes
--  Qué mide: clasifica a los usuarios según su gasto total
--  en viajes para identificar el perfil de viajero predominante.
--  Técnicas: JOIN trips + users, SUM, COUNT, CASE para
--  clasificación, HAVING, subconsulta en SELECT para
--  promedio global de rating de la plataforma.
-- ------------------------------------------------------------
SELECT
    u.status                               AS estatus_cuenta,
    COUNT(t.trip_id)                       AS total_viajes,
    SUM(t.total_budget)                    AS gasto_total,
    CASE
        WHEN SUM(t.total_budget) > 10000 THEN 'Viajero Premium'
        WHEN SUM(t.total_budget) > 3000  THEN 'Viajero Frecuente'
        ELSE                                  'Viajero Ocasional'
    END                                    AS segmento,
    (
        SELECT ROUND(AVG(rating), 2)
        FROM user_travel_history
    )                                      AS rating_promedio_plataforma
FROM users u
JOIN trips t ON t.user_id = u.user_id
WHERE u.deleted_at IS NULL
GROUP BY u.status
HAVING SUM(t.total_budget) > 0
ORDER BY gasto_total DESC;


-- ------------------------------------------------------------
--  Query 4: Destinos más visitados con rating promedio
--  Qué mide: qué países generan más viajes y qué calificación
--  les dan los usuarios al terminarlos.
--  Técnicas: JOIN de 3 tablas (destinations, trips, user_travel_history),
--  COUNT, AVG, HAVING, ORDER BY.
-- ------------------------------------------------------------
SELECT
    d.country                              AS pais,
    d.name                                 AS destino,
    COUNT(t.trip_id)                       AS viajes_generados,
    ROUND(AVG(uth.rating), 2)              AS rating_promedio,
    COUNT(uth.history_id)                  AS veces_completado
FROM destinations d
JOIN trips t
    ON t.destination_id = d.destination_id
LEFT JOIN user_travel_history uth
    ON uth.trip_id = t.trip_id
GROUP BY d.country, d.name
HAVING COUNT(t.trip_id) >= 1
ORDER BY viajes_generados DESC, rating_promedio DESC NULLS LAST;


-- ------------------------------------------------------------
--  Query 5: Wishlist de usuarios que ya completaron un viaje
--  Qué mide: candidatos prioritarios para campañas de marketing,
--  ya que son usuarios activos que terminaron al menos un viaje
--  y tienen destinos en su lista de deseos.
--  Técnicas: JOIN de users + wishlist, subconsulta en WHERE
--  con IN (SELECT DISTINCT ...) sobre trips.
-- ------------------------------------------------------------
SELECT
    u.email                                AS contacto_marketing,
    u.first_name || ' ' || u.last_name     AS nombre,
    w.country                              AS pais_deseado,
    w.city                                 AS ciudad_deseada,
    w.created_at                           AS fecha_agregado
FROM users u
JOIN wishlist w ON w.user_id = u.user_id
WHERE u.deleted_at IS NULL
  AND u.user_id IN (
      SELECT DISTINCT user_id
      FROM trips
      WHERE status = 'COMPLETED'
  )
ORDER BY u.email, w.created_at DESC;


-- ------------------------------------------------------------
--  Query 6: Análisis de etiquetas más usadas por viaje
--  Qué mide: qué etiquetas son más populares entre los viajeros,
--  combinado con el gasto promedio de los viajes que las usan.
--  Técnicas: JOIN de 3 tablas (trip_tags, tags, trips),
--  subconsulta en FROM (tabla derivada), COUNT, AVG, HAVING.
-- ------------------------------------------------------------
SELECT
    base.tag_name,
    base.tag_category,
    base.total_usos,
    ROUND(base.gasto_promedio, 2)          AS gasto_promedio_usd,
    CASE
        WHEN base.gasto_promedio > 5000 THEN 'Viajeros premium'
        WHEN base.gasto_promedio > 1500 THEN 'Viajeros medios'
        ELSE                                  'Viajeros económicos'
    END                                    AS perfil_viajero
FROM (
    SELECT
        tg.name                            AS tag_name,
        tg.category                        AS tag_category,
        COUNT(tt.trip_id)                  AS total_usos,
        COALESCE(AVG(t.total_budget), 0)   AS gasto_promedio
    FROM trip_tags tt
    JOIN tags  tg ON tg.tag_id  = tt.tag_id
    JOIN trips t  ON t.trip_id  = tt.trip_id
    WHERE t.status <> 'CANCELLED'
    GROUP BY tg.name, tg.category
    HAVING COUNT(tt.trip_id) >= 1
) AS base
ORDER BY base.total_usos DESC, base.gasto_promedio DESC;
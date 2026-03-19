-- ============================================================
--  BON VOYAGE — Queries
--  Consultas de Análisis
--  PostgreSQL 16
-- ============================================================

/* 
  Objeto: Query Analítico 1
  1) Qué hace: Cuenta cuántos viajes lograron verdaderamente nuestra métrica de planificarse rápido (menos de 2.5 horas) y nos saca el promedio de horas que invirtió la gente realmente.
  2) Requisito técnico cubierto: Cumplimos con el requisito de "Al menos 1 query directamente vinculado a la métrica de la hipótesis". Hacemos SELECT directo sobre nuestra vista vw_hipotesis_validacion. Usamos COUNT y AVG como funciones de agregación y agrupamos el dictamen usando GROUP BY.
*/
SELECT 
    resultado_hipotesis,
    COUNT(trip_id) AS volumen_de_viajes,
    AVG(horas_planificacion) AS promedio_horas_global
FROM vw_hipotesis_validacion
GROUP BY resultado_hipotesis;


/* 
  Objeto: Query Analítico 2
  1) Qué hace: Agrupa a todos los usuarios cuyos correos de recordatorios están rebotando en el sistema (FAILED). Nos avisa qué asunto falló para detectar si en las pruebas con los 40 usuarios tuvimos cuentas fake o basura.
  2) Requisito técnico cubierto: Nos fuimos al requisito de usar la Cláusula CTE obligatoria, por eso arrancamos con `WITH FallasCorreoCTE AS...`. Unimos las notificaciones con users mediante JOIN. También aplicamos un COALESCE por si acaso un correo no traía Asunto.
*/
WITH FallasCorreoCTE AS (
    SELECT 
        user_id,
        COALESCE(subject, 'Asunto omitido por sistema') AS asunto_resuelto,
        status
    FROM email_notifications
    WHERE status = 'FAILED'
)
SELECT 
    u.first_name || ' ' || u.last_name AS usuario_afectado,
    fc.asunto_resuelto,
    COUNT(fc.user_id) AS total_errores
FROM FallasCorreoCTE fc
JOIN users u ON fc.user_id = u.user_id
GROUP BY u.first_name, u.last_name, fc.asunto_resuelto
HAVING COUNT(fc.user_id) >= 1
ORDER BY total_errores DESC;


/* 
  Objeto: Query Analítico 3
  1) Qué hace: Le pone una etiqueta ("Elite", "Promedio", "Standard") a nuestros usuarios dependiendo de cuánto dinero han sumado en los planes registrados dentro de nuestra plataforma y lo empareja con el rating.
  2) Requisito técnico cubierto: Cumplimos con meter Campos Calculados complejos poniéndole el CASE WHEN para etiquetarlos. Aplicamos agrupación HAVING usando la sumatoria SUM y pusimos la subconsulta estricta del SELECT adentro del mismo query base.
*/
SELECT 
    u.status AS estatus_cuenta,
    COUNT(t.trip_id) AS operaciones_viaje,
    CASE 
        WHEN SUM(t.total_budget) > 10000 THEN 'Cliente Elite'
        WHEN SUM(t.total_budget) > 3000 THEN 'Cliente Promedio'
        ELSE 'Cliente Standard'
    END AS tipo_inversionista,
    SUM(t.total_budget) AS suma_total_capital_invertido,
    (SELECT ROUND(AVG(rating), 2) FROM user_travel_history) AS promedio_rating_general_plataforma
FROM users u
JOIN trips t ON u.user_id = t.user_id
GROUP BY u.status
HAVING SUM(t.total_budget) > 0;


/* 
  Objeto: Query Analítico 4
  1) Qué hace: Escanea cuáles son los países en todo el mundo a los que nuestros turistas han decidido regresar o generar visitas extra.
  2) Requisito técnico cubierto: Demostramos que sabemos unir múltiples dependencias aplicando JOIN sobre 3 tablas consecutivas. Cumplimos usando la función de agregación promediable AVG e ignoramos los recuentos absurdos filtrándole registros al grupo usando el HAVING.
*/
SELECT 
    d.country AS nacion_anfitriona,
    COUNT(t.trip_id) AS visitas_generadas,
    AVG(uth.rating) AS rating_historico_nacion
FROM destinations d
JOIN trips t ON d.destination_id = t.destination_id
LEFT JOIN user_travel_history uth ON t.trip_id = uth.trip_id AND uth.destination = d.name
GROUP BY d.country
HAVING COUNT(t.trip_id) >= 1
ORDER BY visitas_generadas DESC;


/* 
  Objeto: Query Analítico 5
  1) Qué hace: Extrae únicamente datos de listas de deseo (wishlists) de clientes que NOS CONSTA que ya pagaron y terminaron un viaje histórico. Esto lo exportaremos para lanzar correos de venta más agresivos.
  2) Requisito técnico cubierto: Abordamos el requerimiento forzoso de Subconsultas en WHERE insertando la lógica "IN (SELECT DISTINCT...)". Cumplimos también al empatar la lista de deseo mediante JOINs a la raíz de la cuenta del usuario.
*/
SELECT 
    u.email AS usuario_contactar_marketing,
    u.role AS privilegio,
    w.country AS pais_meta,
    w.city AS ciudad_meta
FROM users u
JOIN wishlist w ON u.user_id = w.user_id
WHERE u.user_id IN (
    SELECT DISTINCT user_id 
    FROM trips 
    WHERE status = 'COMPLETED'
)
ORDER BY u.email ASC;

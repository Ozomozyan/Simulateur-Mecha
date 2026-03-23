-- Phase 6.2 — Génération d'events Postgres (7 derniers jours)
-- Scope étendu à 5 usines
-- Production: par minute (06:00-22:00), uniquement sur machines CNC
-- Histoire métier:
--  - FR_TLS / CNC-01: dérive qualité progressive + cycle time qui dérive
--  - ES_ZAZ / CNC-02: arrêts récurrents + arrêt majeur + maintenance corrélée
--  - FR_LYO / FR_LIL / ES_VLC: usines de référence plus saines, avec quelques micro-arrêts réalistes

BEGIN;

TRUNCATE production_events, downtime_events, maintenance_events;

-- Reproductibilité partielle
SELECT setseed(0.4242);

-- 1) Paramètres temps
WITH params AS (
  SELECT
    date_trunc('minute', now()) AS end_ts,
    date_trunc('minute', now()) - interval '7 days' AS start_ts
),

-- 2) Fenêtres d'arrêts (downtime) synthétiques
downtime_windows AS (
  -- ES_ZAZ / CNC-02: arrêts quotidiens (lube) + arrêt majeur (mech fault)
  SELECT
    (d + time '09:30')::timestamptz AS start_ts,
    (d + time '09:45')::timestamptz AS end_ts,
    'PLANT_ES_ZAZ'::text AS plant_code,
    'LINE_ES_B_PM'::text AS line_code,
    'PLANT_ES_ZAZ_CNC-02'::text AS machine_code,
    'LUBE_ALARM'::text AS reason_code
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d

  UNION ALL
  SELECT
    (d + time '15:10')::timestamptz,
    (d + time '15:30')::timestamptz,
    'PLANT_ES_ZAZ','LINE_ES_B_PM','PLANT_ES_ZAZ_CNC-02','UNPLANNED_STOP'
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d

  UNION ALL
  -- Arrêt majeur au milieu de la semaine
  SELECT
    (date_trunc('day', p.start_ts) + interval '3 days' + time '14:00')::timestamptz,
    (date_trunc('day', p.start_ts) + interval '3 days' + time '16:00')::timestamptz,
    'PLANT_ES_ZAZ','LINE_ES_B_PM','PLANT_ES_ZAZ_CNC-02','MECH_FAULT'
  FROM params p

  UNION ALL
  -- FR_TLS: petits arrêts courts sur CNC-02 pour rendre le cockpit réaliste
  SELECT
    (d + time '11:20')::timestamptz,
    (d + time '11:27')::timestamptz,
    'PLANT_FR_TLS','LINE_FR_A_PM','PLANT_FR_TLS_CNC-02','UNPLANNED_STOP'
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d

  UNION ALL
  -- FR_LYO: usine saine avec petit arrêt court quotidien
  SELECT
    (d + time '13:05')::timestamptz,
    (d + time '13:13')::timestamptz,
    'PLANT_FR_LYO','LINE_FR_C_PM','PLANT_FR_LYO_CNC-02','UNPLANNED_STOP'
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d

  UNION ALL
  -- FR_LIL: usine saine avec petit arrêt court quotidien
  SELECT
    (d + time '10:40')::timestamptz,
    (d + time '10:46')::timestamptz,
    'PLANT_FR_LIL','LINE_FR_D_PM','PLANT_FR_LIL_CNC-02','UNPLANNED_STOP'
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d

  UNION ALL
  -- ES_VLC: petite alerte lubrification quotidienne
  SELECT
    (d + time '12:15')::timestamptz,
    (d + time '12:24')::timestamptz,
    'PLANT_ES_VLC','LINE_ES_E_PM','PLANT_ES_VLC_CNC-02','LUBE_ALARM'
  FROM params p
  CROSS JOIN generate_series(date_trunc('day', p.start_ts), date_trunc('day', p.end_ts), interval '1 day') d
)

-- 3) Insert downtime_events
INSERT INTO downtime_events (start_ts, end_ts, plant_code, line_code, machine_code, reason_code)
SELECT start_ts, end_ts, plant_code, line_code, machine_code, reason_code
FROM downtime_windows;

-- 4) Insert maintenance_events corrélés (quand reason_code = maintenance)
INSERT INTO maintenance_events (ts, plant_code, line_code, machine_code, maintenance_type, action_code)
SELECT
  dw.start_ts + interval '2 minutes' AS ts,
  dw.plant_code,
  dw.line_code,
  dw.machine_code,
  CASE
    WHEN dw.reason_code = 'LUBE_ALARM' THEN 'preventive'
    WHEN dw.reason_code = 'MECH_FAULT' THEN 'corrective'
    ELSE 'inspection'
  END AS maintenance_type,
  CASE
    WHEN dw.reason_code = 'LUBE_ALARM' THEN 'REFILL_LUBE'
    WHEN dw.reason_code = 'MECH_FAULT' THEN 'REPLACE_BEARING'
    ELSE NULL
  END AS action_code
FROM downtime_events dw
WHERE dw.reason_code IN ('LUBE_ALARM', 'MECH_FAULT');

-- 5) Insert production_events (par minute) hors downtime, shift 06:00-22:00
WITH params AS (
  SELECT
    date_trunc('minute', now()) AS end_ts,
    date_trunc('minute', now()) - interval '7 days' AS start_ts,
    EXTRACT(EPOCH FROM interval '7 days')::double precision AS total_span_s
),
cnb AS (
  SELECT
    m.machine_code,
    m.machine_name,
    m.machine_type,
    l.line_code,
    l.plant_code,
    p2.ideal_cycle_time_s
  FROM machines m
  JOIN lines l ON l.line_code = m.line_code
  JOIN products p2 ON p2.product_id = 'P_INJECTOR_PIN'
  WHERE m.machine_type = 'CNC'
),
minutes AS (
  SELECT gs AS ts
  FROM params p
  CROSS JOIN generate_series(p.start_ts, p.end_ts, interval '1 minute') gs
  WHERE EXTRACT(HOUR FROM gs) >= 6
    AND EXTRACT(HOUR FROM gs) < 22
),
grid AS (
  SELECT
    mn.ts,
    c.plant_code,
    c.line_code,
    c.machine_code,
    c.machine_name,
    c.ideal_cycle_time_s,
    LEAST(
      1.0,
      GREATEST(0.0, EXTRACT(EPOCH FROM (mn.ts - p.start_ts)) / p.total_span_s)
    ) AS progress
  FROM minutes mn
  CROSS JOIN params p
  CROSS JOIN cnb c
),
running AS (
  SELECT g.*
  FROM grid g
  WHERE NOT EXISTS (
    SELECT 1
    FROM downtime_events d
    WHERE d.machine_code = g.machine_code
      AND g.ts >= d.start_ts
      AND g.ts < d.end_ts
  )
),
computed AS (
  SELECT
    ts,
    plant_code,
    line_code,
    machine_code,
    machine_name,
    'P_INJECTOR_PIN'::text AS product_id,

    -- scrap probability (story-driven)
    CASE
      WHEN plant_code = 'PLANT_FR_TLS' AND machine_name = 'CNC-01'
        THEN 0.01 + 0.05 * progress          -- dérive FR_TLS CNC-01: 1% -> 6%
      WHEN plant_code = 'PLANT_ES_ZAZ'
        THEN 0.015                           -- un peu plus instable
      WHEN plant_code = 'PLANT_ES_VLC'
        THEN 0.013                           -- légère variabilité
      ELSE 0.010                            -- usines de référence plus propres
    END AS scrap_p,

    -- cycle time factor: bruit + dérive sur FR_TLS CNC-01
    (
      1.0
      + (random() - 0.5) * 0.08              -- ±4% noise
      + CASE
          WHEN plant_code = 'PLANT_FR_TLS' AND machine_name = 'CNC-01'
            THEN 0.20 * progress             -- jusqu'à +20%
          WHEN plant_code = 'PLANT_ES_ZAZ' AND machine_name = 'CNC-02'
            THEN 0.04                        -- légère pénalité structurelle
          ELSE 0.0
        END
    ) AS cycle_factor
  FROM running
),
counts AS (
  SELECT
    ts,
    plant_code,
    line_code,
    machine_code,
    product_id,
    CASE WHEN random() < 0.65 THEN 1 ELSE 2 END AS total_parts,
    scrap_p,
    cycle_factor
  FROM computed
)
INSERT INTO production_events (
  ts,
  plant_code,
  line_code,
  machine_code,
  product_id,
  good_count,
  scrap_count,
  cycle_time_s
)
SELECT
  ts,
  plant_code,
  line_code,
  machine_code,
  product_id,
  GREATEST(total_parts - scrap_count, 0) AS good_count,
  scrap_count,
  (40.0 * cycle_factor)::numeric(10,2) AS cycle_time_s
FROM (
  SELECT
    *,
    CASE WHEN random() < scrap_p THEN 1 ELSE 0 END AS scrap_count
  FROM counts
) x;

-- Indexes utiles pour Grafana
CREATE INDEX IF NOT EXISTS idx_prod_ts ON production_events (ts);
CREATE INDEX IF NOT EXISTS idx_prod_machine_ts ON production_events (machine_code, ts);
CREATE INDEX IF NOT EXISTS idx_down_machine_ts ON downtime_events (machine_code, start_ts);

COMMIT;
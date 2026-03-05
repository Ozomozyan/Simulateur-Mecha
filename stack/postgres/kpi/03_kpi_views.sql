BEGIN;

-- 1) Production agrégée par heure
CREATE OR REPLACE VIEW v_prod_hourly AS
SELECT
  date_trunc('hour', ts) AS hour,
  plant_code,
  line_code,
  machine_code,
  product_id,
  SUM(good_count) AS good,
  SUM(scrap_count) AS scrap,
  (SUM(good_count) + SUM(scrap_count)) AS total,
  AVG(cycle_time_s) AS avg_cycle_s
FROM production_events
GROUP BY 1,2,3,4,5;

-- 2) Downtime par heure (PROPRE: on découpe un arrêt qui traverse plusieurs heures)
CREATE OR REPLACE VIEW v_downtime_hourly AS
SELECT
  bucket AS hour,
  plant_code,
  line_code,
  machine_code,
  SUM(EXTRACT(EPOCH FROM (LEAST(end_ts, bucket + interval '1 hour') - GREATEST(start_ts, bucket))) / 60.0) AS downtime_min,
  COUNT(*) AS downtime_events
FROM downtime_events
CROSS JOIN LATERAL generate_series(
  date_trunc('hour', start_ts),
  date_trunc('hour', end_ts),
  interval '1 hour'
) AS bucket
WHERE bucket < end_ts
GROUP BY 1,2,3,4;

-- 3) Maintenance par heure
CREATE OR REPLACE VIEW v_maintenance_hourly AS
SELECT
  date_trunc('hour', ts) AS hour,
  plant_code,
  line_code,
  machine_code,
  COUNT(*) AS maintenance_count
FROM maintenance_events
GROUP BY 1,2,3,4;

-- 4) KPI machine par heure (OEE + scrap + cycle + throughput + maintenance + downtime)
-- Assumption PoC: période planifiée = 06:00-22:00 (16h). Documentez-le dans le dossier.
CREATE OR REPLACE VIEW kpi_machine_hourly AS
SELECT
  p.hour,
  p.plant_code,
  p.line_code,
  p.machine_code,
  m.machine_name,
  p.product_id,
  p.good,
  p.scrap,
  p.total,
  ROUND(p.scrap::numeric / NULLIF(p.total,0), 4) AS scrap_rate,
  ROUND(p.avg_cycle_s::numeric, 2) AS avg_cycle_s,
  pr.ideal_cycle_time_s,
  ROUND(((p.avg_cycle_s - pr.ideal_cycle_time_s) / NULLIF(pr.ideal_cycle_time_s,0))::numeric, 4) AS cycle_drift_pct,
  ROUND((p.total::numeric / 1.0), 2) AS throughput_parts_per_hour, -- total agrégé sur 1h

  -- planned minutes: 60 si dans la fenêtre 06-22, sinon 0
  CASE
    WHEN EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') >= 6
     AND EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') < 22 THEN 60
    ELSE 0
  END AS planned_min,

  COALESCE(ROUND(d.downtime_min::numeric, 1), 0) AS downtime_min,
  COALESCE(d.downtime_events, 0) AS downtime_events,
  COALESCE(ma.maintenance_count, 0) AS maintenance_count,

  -- Quality
  ROUND((p.good::numeric / NULLIF(p.total,0)), 4) AS quality_rate,

  -- Performance (proxy)
  ROUND((pr.ideal_cycle_time_s / NULLIF(p.avg_cycle_s,0))::numeric, 4) AS performance_rate,

  -- Availability
  CASE
    WHEN (CASE WHEN EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') >= 6 AND EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') < 22 THEN 60 ELSE 0 END) = 0
      THEN NULL
    ELSE
      ROUND(((60 - COALESCE(d.downtime_min,0)) / 60.0)::numeric, 4)
  END AS availability_rate,

  -- OEE/TRS
  CASE
    WHEN (CASE WHEN EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') >= 6 AND EXTRACT(HOUR FROM p.hour AT TIME ZONE 'UTC') < 22 THEN 60 ELSE 0 END) = 0
      THEN NULL
    ELSE
      ROUND(
        (
          ((60 - COALESCE(d.downtime_min,0)) / 60.0)
          * (pr.ideal_cycle_time_s / NULLIF(p.avg_cycle_s,0))
          * (p.good::numeric / NULLIF(p.total,0))
        )::numeric
      , 4)
  END AS oee
FROM v_prod_hourly p
JOIN products pr ON pr.product_id = p.product_id
JOIN machines m ON m.machine_code = p.machine_code
LEFT JOIN v_downtime_hourly d
  ON d.hour = p.hour
 AND d.plant_code = p.plant_code
 AND d.line_code = p.line_code
 AND d.machine_code = p.machine_code
LEFT JOIN v_maintenance_hourly ma
  ON ma.hour = p.hour
 AND ma.plant_code = p.plant_code
 AND ma.line_code = p.line_code
 AND ma.machine_code = p.machine_code;

-- 5) KPI machine par jour (rebuts journalier demandé + synthèse)
CREATE OR REPLACE VIEW kpi_machine_daily AS
SELECT
  date_trunc('day', hour) AS day,
  plant_code,
  line_code,
  machine_code,
  machine_name,
  ROUND(AVG(oee)::numeric, 4) AS oee_avg,
  ROUND(AVG(availability_rate)::numeric, 4) AS availability_avg,
  ROUND(AVG(performance_rate)::numeric, 4) AS performance_avg,
  ROUND(AVG(quality_rate)::numeric, 4) AS quality_avg,
  ROUND(AVG(avg_cycle_s)::numeric, 2) AS avg_cycle_s,
  ROUND(AVG(cycle_drift_pct)::numeric, 4) AS cycle_drift_pct_avg,
  SUM(good) AS good,
  SUM(scrap) AS scrap,
  ROUND(SUM(scrap)::numeric / NULLIF(SUM(total),0), 4) AS scrap_rate_daily,
  ROUND(SUM(downtime_min)::numeric, 1) AS downtime_min,
  SUM(maintenance_count) AS maintenance_count
FROM kpi_machine_hourly
WHERE planned_min > 0
GROUP BY 1,2,3,4,5;

-- 6) KPI usine par jour (Cockpit Groupe)
CREATE OR REPLACE VIEW kpi_plant_daily AS
SELECT
  day,
  plant_code,
  ROUND(AVG(oee_avg)::numeric, 4) AS oee_avg,
  ROUND(AVG(scrap_rate_daily)::numeric, 4) AS scrap_rate_daily_avg,
  ROUND(SUM(downtime_min)::numeric, 1) AS downtime_min,
  SUM(good) AS good,
  SUM(scrap) AS scrap,
  SUM(maintenance_count) AS maintenance_count
FROM kpi_machine_daily
GROUP BY 1,2;

-- 7) Dispo “machine principale” (CNC-01) par jour
CREATE OR REPLACE VIEW kpi_main_machine_daily AS
SELECT *
FROM kpi_machine_daily
WHERE machine_name = 'CNC-01';

-- 8) Pareto causes d'arrêts (par jour)
CREATE OR REPLACE VIEW kpi_downtime_pareto_daily AS
SELECT
  date_trunc('day', start_ts) AS day,
  plant_code,
  machine_code,
  reason_code,
  ROUND(SUM(EXTRACT(EPOCH FROM (end_ts - start_ts)) / 60.0)::numeric, 1) AS downtime_min
FROM downtime_events
GROUP BY 1,2,3,4;

COMMIT;
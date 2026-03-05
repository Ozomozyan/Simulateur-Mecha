# Start stack
docker compose up -d

# Generate events (Phase 6.2)
Get-Content .\postgres\demo\02_generate_events.sql -Raw | docker compose exec -T postgres psql -U mecha -d mecha

# Create / refresh KPI views (Phase 7)
Get-Content .\postgres\kpi\03_kpi_views.sql -Raw | docker compose exec -T postgres psql -U mecha -d mecha

# Smoke test
docker compose exec -T postgres psql -U mecha -d mecha -c "
SELECT 'production_events' AS t, COUNT(*) AS n FROM production_events
UNION ALL SELECT 'downtime_events', COUNT(*) FROM downtime_events
UNION ALL SELECT 'maintenance_events', COUNT(*) FROM maintenance_events;
SELECT * FROM kpi_plant_daily ORDER BY day, plant_code;"
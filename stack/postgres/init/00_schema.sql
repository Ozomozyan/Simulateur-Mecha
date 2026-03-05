BEGIN;

-- Dimensions
CREATE TABLE IF NOT EXISTS plants (
  plant_code TEXT PRIMARY KEY,
  plant_name TEXT NOT NULL,
  country TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS lines (
  line_code TEXT PRIMARY KEY,
  plant_code TEXT NOT NULL REFERENCES plants(plant_code),
  line_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS machines (
  machine_code TEXT PRIMARY KEY,
  line_code TEXT NOT NULL REFERENCES lines(line_code),
  machine_name TEXT NOT NULL,
  machine_type TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS products (
  product_id TEXT PRIMARY KEY,
  product_name TEXT NOT NULL,
  ideal_cycle_time_s NUMERIC NOT NULL
);

CREATE TABLE IF NOT EXISTS reason_codes (
  reason_code TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  description TEXT NOT NULL
);

-- Facts (events)
CREATE TABLE IF NOT EXISTS production_events (
  ts TIMESTAMPTZ NOT NULL,
  plant_code TEXT NOT NULL REFERENCES plants(plant_code),
  line_code TEXT NOT NULL REFERENCES lines(line_code),
  machine_code TEXT NOT NULL REFERENCES machines(machine_code),
  product_id TEXT NOT NULL REFERENCES products(product_id),
  good_count INT NOT NULL,
  scrap_count INT NOT NULL,
  cycle_time_s NUMERIC NOT NULL
);

CREATE TABLE IF NOT EXISTS downtime_events (
  start_ts TIMESTAMPTZ NOT NULL,
  end_ts TIMESTAMPTZ NOT NULL,
  plant_code TEXT NOT NULL REFERENCES plants(plant_code),
  line_code TEXT NOT NULL REFERENCES lines(line_code),
  machine_code TEXT NOT NULL REFERENCES machines(machine_code),
  reason_code TEXT NOT NULL REFERENCES reason_codes(reason_code)
);

CREATE TABLE IF NOT EXISTS maintenance_events (
  ts TIMESTAMPTZ NOT NULL,
  plant_code TEXT NOT NULL REFERENCES plants(plant_code),
  line_code TEXT NOT NULL REFERENCES lines(line_code),
  machine_code TEXT NOT NULL REFERENCES machines(machine_code),
  maintenance_type TEXT NOT NULL,
  action_code TEXT
);

-- Index utiles
CREATE INDEX IF NOT EXISTS idx_prod_ts ON production_events (ts);
CREATE INDEX IF NOT EXISTS idx_prod_machine_ts ON production_events (machine_code, ts);
CREATE INDEX IF NOT EXISTS idx_down_machine_ts ON downtime_events (machine_code, start_ts);

COMMIT;
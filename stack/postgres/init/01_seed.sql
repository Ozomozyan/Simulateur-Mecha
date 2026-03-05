BEGIN;

INSERT INTO plants (plant_code, plant_name, country) VALUES
('PLANT_FR_TLS','MECHA_FR_Toulouse','FR'),
('PLANT_ES_ZAZ','MECHA_ES_Zaragoza','ES')
ON CONFLICT (plant_code) DO NOTHING;

INSERT INTO lines (line_code, plant_code, line_name) VALUES
('LINE_FR_A_PM','PLANT_FR_TLS','LINE_A_PrecisionMachining'),
('LINE_ES_B_PM','PLANT_ES_ZAZ','LINE_B_PrecisionMachining')
ON CONFLICT (line_code) DO NOTHING;

INSERT INTO machines (machine_code, line_code, machine_name, machine_type) VALUES
('PLANT_FR_TLS_CNC-01','LINE_FR_A_PM','CNC-01','CNC'),
('PLANT_FR_TLS_CNC-02','LINE_FR_A_PM','CNC-02','CNC'),
('PLANT_FR_TLS_QC-01','LINE_FR_A_PM','QC-01','QC'),
('PLANT_ES_ZAZ_CNC-01','LINE_ES_B_PM','CNC-01','CNC'),
('PLANT_ES_ZAZ_CNC-02','LINE_ES_B_PM','CNC-02','CNC'),
('PLANT_ES_ZAZ_QC-01','LINE_ES_B_PM','QC-01','QC')
ON CONFLICT (machine_code) DO NOTHING;

INSERT INTO products (product_id, product_name, ideal_cycle_time_s) VALUES
('P_INJECTOR_PIN','Injector precision pin', 40)
ON CONFLICT (product_id) DO NOTHING;

INSERT INTO reason_codes (reason_code, category, description) VALUES
('MECH_FAULT','maintenance','Mechanical fault'),
('LUBE_ALARM','maintenance','Lubrication alarm'),
('OVERTEMP','process','Over temperature'),
('UNPLANNED_STOP','production','Unplanned stop')
ON CONFLICT (reason_code) DO NOTHING;

COMMIT;
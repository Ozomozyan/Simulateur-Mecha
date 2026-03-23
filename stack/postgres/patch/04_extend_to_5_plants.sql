BEGIN;

-- 3 new plants
INSERT INTO plants (plant_code, plant_name, country) VALUES
('PLANT_FR_LYO','MECHA_FR_Lyon','FR'),
('PLANT_FR_LIL','MECHA_FR_Lille','FR'),
('PLANT_ES_VLC','MECHA_ES_Valencia','ES')
ON CONFLICT (plant_code) DO NOTHING;

-- 3 new lines
INSERT INTO lines (line_code, plant_code, line_name) VALUES
('LINE_FR_C_PM','PLANT_FR_LYO','LINE_C_PrecisionMachining'),
('LINE_FR_D_PM','PLANT_FR_LIL','LINE_D_PrecisionMachining'),
('LINE_ES_E_PM','PLANT_ES_VLC','LINE_E_PrecisionMachining')
ON CONFLICT (line_code) DO NOTHING;

-- 9 new machines (3 per plant)
INSERT INTO machines (machine_code, line_code, machine_name, machine_type) VALUES
('PLANT_FR_LYO_CNC-01','LINE_FR_C_PM','CNC-01','CNC'),
('PLANT_FR_LYO_CNC-02','LINE_FR_C_PM','CNC-02','CNC'),
('PLANT_FR_LYO_QC-01','LINE_FR_C_PM','QC-01','QC'),

('PLANT_FR_LIL_CNC-01','LINE_FR_D_PM','CNC-01','CNC'),
('PLANT_FR_LIL_CNC-02','LINE_FR_D_PM','CNC-02','CNC'),
('PLANT_FR_LIL_QC-01','LINE_FR_D_PM','QC-01','QC'),

('PLANT_ES_VLC_CNC-01','LINE_ES_E_PM','CNC-01','CNC'),
('PLANT_ES_VLC_CNC-02','LINE_ES_E_PM','CNC-02','CNC'),
('PLANT_ES_VLC_QC-01','LINE_ES_E_PM','QC-01','QC')
ON CONFLICT (machine_code) DO NOTHING;

COMMIT;
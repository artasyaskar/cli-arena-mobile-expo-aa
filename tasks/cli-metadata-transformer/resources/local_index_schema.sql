-- This file can be used to initialize the SQLite database schema if not defined in transformation_rules.json
-- However, the primary schema definition is expected to be within transformation_rules.json
-- for dynamic table creation based on transformations.

-- Example of a generic schema if rules don't define one (though the task specifies rules.json should define it)
-- CREATE TABLE IF NOT EXISTS indexed_records (
--     id TEXT PRIMARY KEY,
--     source_table TEXT,
--     transformed_data TEXT, -- JSON blob of the transformed record
--     indexed_at TEXT
-- );

-- CREATE INDEX IF NOT EXISTS idx_records_source_table ON indexed_records (source_table);
-- CREATE INDEX IF NOT EXISTS idx_records_indexed_at ON indexed_records (indexed_at);

-- For this specific task, the schema is dynamically generated from transformation_rules.json.
-- This file can serve as a placeholder or for auxiliary tables if needed.
-- For instance, a table to store metadata about indexing runs:
CREATE TABLE IF NOT EXISTS etl_runs (
    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    status TEXT, -- e.g., 'started', 'completed', 'failed'
    records_processed INTEGER,
    error_message TEXT
);

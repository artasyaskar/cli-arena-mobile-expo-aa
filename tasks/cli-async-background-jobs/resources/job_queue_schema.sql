CREATE TABLE IF NOT EXISTS jobs (
    job_id TEXT PRIMARY KEY,
    job_name TEXT,
    command TEXT NOT NULL,
    args TEXT, -- JSON array of arguments, or space-separated string
    status TEXT NOT NULL DEFAULT 'pending', -- pending, running, succeeded, failed, cancelled, retrying
    submit_time TEXT NOT NULL, -- ISO8601 timestamp
    scheduled_time TEXT NOT NULL, -- ISO8601 timestamp
    start_time TEXT, -- ISO8601 timestamp, when execution began
    end_time TEXT, -- ISO8601 timestamp, when execution finished
    exit_code INTEGER,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    next_retry_time TEXT, -- ISO8601 timestamp, only if status is 'retrying'
    stdout_log_path TEXT,
    stderr_log_path TEXT,
    worker_pid INTEGER, -- PID of the process-queue instance that picked up this job
    last_error TEXT -- Store last error message if any
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
CREATE INDEX IF NOT EXISTS idx_jobs_scheduled_time ON jobs(scheduled_time);
CREATE INDEX IF NOT EXISTS idx_jobs_next_retry_time ON jobs(next_retry_time);
CREATE INDEX IF NOT EXISTS idx_jobs_job_name ON jobs(job_name);

-- Optional: Table for storing historical job logs if stdout/stderr are large
-- CREATE TABLE IF NOT EXISTS job_run_logs (
--    run_id INTEGER PRIMARY KEY AUTOINCREMENT,
--    job_id TEXT NOT NULL,
--    attempt_number INTEGER NOT NULL,
--    run_start_time TEXT NOT NULL,
--    run_end_time TEXT,
--    run_exit_code INTEGER,
--    stdout_content TEXT, -- Or path to file if very large
--    stderr_content TEXT, -- Or path to file
--    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
-- );
-- For this task, stdout_log_path and stderr_log_path in the main table will point to files.

-- Configuration table (optional, for things like default_max_retries if not hardcoded)
-- CREATE TABLE IF NOT EXISTS job_config (
--    key TEXT PRIMARY KEY,
--    value TEXT
-- );
-- INSERT OR IGNORE INTO job_config (key, value) VALUES ('default_max_retries', '3');
-- INSERT OR IGNORE INTO job_config (key, value) VALUES ('default_base_retry_delay_seconds', '5');

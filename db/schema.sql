-- ========================================
-- CREATE supabase_admin ROLE IF NOT EXISTS
-- ========================================
DO
$$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'supabase_admin') THEN
      CREATE ROLE supabase_admin;
   END IF;
END
$$;

-- ========================================
-- GRANT supabase_admin TO postgres
-- ========================================
GRANT supabase_admin TO postgres;

-- ========================================
-- RESET ANY PREVIOUSLY SET ROLE
-- ========================================
RESET ROLE;

-- ========================================
-- EXTENSIONS
-- ========================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ========================================
-- TABLES AND FUNCTIONS
-- ========================================
CREATE TABLE IF NOT EXISTS public.test_table (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);


CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY,
  username TEXT
);

-- ========================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual read access to own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Allow individual update access to own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  name TEXT NOT NULL UNIQUE,
  owner_id UUID,
  CONSTRAINT name_length CHECK (char_length(name) > 0)
);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.organization_members (
  organization_id UUID NOT NULL,
  user_id UUID NOT NULL,
  role TEXT NOT NULL DEFAULT 'member',
  joined_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  PRIMARY KEY (organization_id, user_id)
);

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.user_actions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  action_type TEXT NOT NULL,
  payload JSONB,
  created_at_client TIMESTAMPTZ NOT NULL,
  synced_at TIMESTAMPTZ,
  status TEXT DEFAULT 'pending',
  device_id TEXT,
  client_action_id TEXT UNIQUE
);

ALTER TABLE public.user_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual insert access for own actions"
  ON public.user_actions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Allow individual read/update access for own pending/failed actions"
  ON public.user_actions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id AND status IN ('pending', 'failed', 'conflict'));

CREATE TABLE IF NOT EXISTS public.secure_items_metadata (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  item_key TEXT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  UNIQUE (user_id, item_key)
);

ALTER TABLE public.secure_items_metadata ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual access to own secure items metadata"
  ON public.secure_items_metadata FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.location_audits (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL,
  latitude DECIMAL(9,6) NOT NULL,
  longitude DECIMAL(9,6) NOT NULL,
  accuracy DECIMAL(10,2),
  timestamp TIMESTAMPTZ NOT NULL,
  recorded_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  source TEXT
);

ALTER TABLE public.location_audits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual insert access for own location data"
  ON public.location_audits FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Allow individual read access to own location data"
  ON public.location_audits FOR SELECT
  USING (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.background_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  job_type TEXT NOT NULL,
  payload JSONB,
  status TEXT DEFAULT 'pending',
  attempts INT DEFAULT 0,
  max_attempts INT DEFAULT 5,
  last_attempted_at TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()),
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.background_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual read access to own background jobs"
  ON public.background_jobs FOR SELECT
  USING (auth.uid() = user_id AND user_id IS NOT NULL);

CREATE POLICY "Allow individual insert access for own background jobs"
  ON public.background_jobs FOR INSERT
  WITH CHECK (auth.uid() = user_id AND user_id IS NOT NULL);

CREATE TABLE IF NOT EXISTS public.error_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  error_code TEXT NOT NULL,
  message_template_key TEXT,
  context JSONB,
  client_locale VARCHAR(10),
  platform_info JSONB,
  stack_trace TEXT,
  reported_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.error_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous or authenticated insert access for error reports"
  ON public.error_reports FOR INSERT
  WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.app_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  device_id TEXT,
  last_active_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.app_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual access to own app sessions"
  ON public.app_sessions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.file_metadata (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  organization_id UUID,
  storage_path TEXT NOT NULL UNIQUE,
  bucket_id TEXT NOT NULL DEFAULT 'general',
  file_name TEXT NOT NULL,
  mime_type TEXT,
  size_bytes BIGINT,
  metadata JSONB,
  upload_status TEXT DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.file_metadata ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual access to own file metadata"
  ON public.file_metadata FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.indexed_cli_records (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  source_table TEXT NOT NULL,
  source_record_id TEXT NOT NULL,
  transformed_data JSONB NOT NULL,
  indexed_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  version INT DEFAULT 1,
  UNIQUE (source_table, source_record_id)
);

ALTER TABLE public.indexed_cli_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual read access to own indexed records"
  ON public.indexed_cli_records FOR SELECT
  USING (auth.uid() = user_id AND user_id IS NOT NULL);

CREATE TABLE IF NOT EXISTS public.offline_form_submissions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL,
  form_id TEXT NOT NULL,
  data JSONB NOT NULL,
  client_submitted_at TIMESTAMPTZ NOT NULL,
  status TEXT DEFAULT 'pending',
  server_replayed_at TIMESTAMPTZ,
  error_details TEXT,
  device_id TEXT
);

ALTER TABLE public.offline_form_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow individual access to own offline form submissions"
  ON public.offline_form_submissions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ========================================
-- TIMESTAMP TRIGGERS
-- ========================================
CREATE OR REPLACE FUNCTION public.trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
BEFORE UPDATE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_secure_items_metadata_updated_at ON public.secure_items_metadata;
CREATE TRIGGER set_secure_items_metadata_updated_at
BEFORE UPDATE ON public.secure_items_metadata
FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_background_jobs_updated_at ON public.background_jobs;
CREATE TRIGGER set_background_jobs_updated_at
BEFORE UPDATE ON public.background_jobs
FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

DROP TRIGGER IF EXISTS set_file_metadata_updated_at ON public.file_metadata;
CREATE TRIGGER set_file_metadata_updated_at
BEFORE UPDATE ON public.file_metadata
FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

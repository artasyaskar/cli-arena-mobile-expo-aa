-- ============================================================
-- Grant Superuser (must be run early to allow extension creation)
-- ============================================================
ALTER ROLE postgres WITH SUPERUSER;

-- ============================================================
-- Extensions (ensure uuid_generate_v4() is available)
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- Seed Organizations
-- ============================================================
INSERT INTO public.organizations (id, name, owner_id)
VALUES
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11', 'Global Dynamics Inc.', NULL),
  ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12', 'Cyberdyne Systems LLC', NULL)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Table: generic_items
-- ============================================================
CREATE TABLE IF NOT EXISTS public.generic_items (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

ALTER TABLE public.generic_items ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Triggers
-- ============================================================
CREATE TRIGGER set_generic_items_updated_at
BEFORE UPDATE ON public.generic_items
FOR EACH ROW EXECUTE FUNCTION public.trigger_set_timestamp();

-- ============================================================
-- Seed Generic Items
-- NOTE: user_id is NULL for now — replace with real UUID if needed
-- ============================================================
INSERT INTO public.generic_items (
  id, user_id, organization_id, name, description, details
)
VALUES
  (
    'c1f8e4d9-0b7e-4b1f-8c7a-6d5e4f3a2b10',
    NULL,
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'Project Alpha',
    'Initial project for Global Dynamics.',
    '{"priority": "high", "status": "active"}'
  ),
  (
    'd2e7f5c8-1a6d-4c0e-9b5b-5e4f3a2b1c11',
    NULL,
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a12',
    'Skynet Prototype',
    'Early AI development at Cyberdyne.',
    '{"version": "0.1", "confidential": true}'
  )
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Done
-- ============================================================
\echo '✅ Seed data script complete.'

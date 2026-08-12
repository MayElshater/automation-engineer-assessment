-- Lead Automation Platform - PostgreSQL/Supabase schema

-- =============================================================================
-- Extensions
-- =============================================================================
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- =============================================================================
-- Sales representatives (created before leads for foreign-key consistency)
-- =============================================================================
CREATE TABLE IF NOT EXISTS sales_reps (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL,
 service_categories text[] NOT NULL DEFAULT ARRAY[]::text[], countries text[] NOT NULL DEFAULT ARRAY[]::text[],
 active boolean NOT NULL DEFAULT true, current_load integer NOT NULL DEFAULT 0 CHECK (current_load >= 0),
 max_load integer NOT NULL DEFAULT 0 CHECK (max_load >= 0), created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Leads
-- =============================================================================
CREATE TABLE IF NOT EXISTS leads (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), source text NOT NULL, external_source_id text, received_at timestamptz NOT NULL DEFAULT now(),
 name text, phone_raw text, phone_normalized text, email_raw text, email_normalized text, consent boolean NOT NULL DEFAULT false,
 company_name text, service_interest text, country text, industry text, company_size integer, strategic_account boolean NOT NULL DEFAULT false, message text,
 validation_status text
 NOT NULL
 DEFAULT 'pending'
 CHECK (
     validation_status IN (
         'pending',
         'valid',
         'incomplete',
         'invalid'
     )
 ), identity_status text NOT NULL DEFAULT 'pending',
 rule_score integer DEFAULT 0 CHECK (rule_score BETWEEN 0 AND 100), rule_classification text, ai_classification text,
 ai_confidence numeric(5,4) CHECK (ai_confidence BETWEEN 0 AND 1), final_status text, qualification_reason text, is_vip boolean NOT NULL DEFAULT false,
 assigned_sales_rep_id uuid REFERENCES sales_reps(id) ON DELETE SET NULL, priority text CHECK (priority IN ('low','medium','high','critical')),
 odoo_lead_id text, crm_stage text, next_action text, processing_status text
 NOT NULL
 DEFAULT 'processing'
 CHECK (
     processing_status IN (
         'processing',
         'completed',
         'failed',
         'manual_review'
     )
 ),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT leads_source_external_source_id_key UNIQUE (source, external_source_id)
);

-- =============================================================================
-- Lead audit trail
-- Example event types: lead_received, normalized, validation_failed,
-- data_completed, duplicate_detected, duplicate_merged, enrichment_completed,
-- qualification_completed, manual_review_requested, sales_assigned, crm_synced,
-- message_sent, followup_sent, meeting_booked, sla_breached, failed, reprocessed
-- =============================================================================
CREATE TABLE IF NOT EXISTS lead_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
 event_type text NOT NULL, workflow_name text, execution_id text, payload jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Idempotency
-- =============================================================================
CREATE TABLE IF NOT EXISTS idempotency_keys (
 key text PRIMARY KEY, operation text NOT NULL, lead_id uuid REFERENCES leads(id) ON DELETE SET NULL,
 status text NOT NULL DEFAULT 'processing', response_reference text, created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz,
 CHECK (expires_at IS NULL OR expires_at > created_at)
);

-- =============================================================================
-- Duplicate detection decisions
-- candidate_lead_id identifies the incoming duplicate submission and may
-- intentionally not exist in leads because leads stores canonical records only.
-- matched_lead_id identifies the canonical lead and therefore retains its FK.
-- =============================================================================
CREATE TABLE IF NOT EXISTS duplicate_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), candidate_lead_id uuid NOT NULL,
 matched_lead_id uuid REFERENCES leads(id) ON DELETE SET NULL, match_type text NOT NULL,
 confidence numeric(5,4) CHECK (confidence BETWEEN 0 AND 1), decision text NOT NULL, reason text, reviewed_by text,
 created_at timestamptz NOT NULL DEFAULT now(), CHECK (candidate_lead_id <> matched_lead_id)
);

-- Remove the legacy candidate FK safely when upgrading an existing deployment.
ALTER TABLE IF EXISTS duplicate_decisions
 DROP CONSTRAINT IF EXISTS duplicate_decisions_candidate_lead_id_fkey;

-- =============================================================================
-- Follow-up sequences
-- =============================================================================
CREATE TABLE IF NOT EXISTS followups (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
 sequence_type text NOT NULL, step_number integer NOT NULL CHECK (step_number > 0), scheduled_at timestamptz NOT NULL,
 executed_at timestamptz, status text NOT NULL DEFAULT 'scheduled',
 idempotency_key text UNIQUE REFERENCES idempotency_keys(key) ON DELETE SET NULL, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE (lead_id, sequence_type, step_number)
);

-- =============================================================================
-- Manager approvals
-- =============================================================================
CREATE TABLE IF NOT EXISTS manager_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
 status text NOT NULL DEFAULT 'pending', requested_at timestamptz NOT NULL DEFAULT now(), responded_at timestamptz,
 manager text, reason text, CHECK (responded_at IS NULL OR responded_at >= requested_at)
);

-- =============================================================================
-- Bookings
-- =============================================================================
CREATE TABLE IF NOT EXISTS bookings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lead_id uuid NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
 external_booking_id text NOT NULL UNIQUE, meeting_at timestamptz NOT NULL, status text NOT NULL DEFAULT 'scheduled', created_at timestamptz NOT NULL DEFAULT now()
);

-- =============================================================================
-- Dead-letter queue
-- =============================================================================
CREATE TABLE IF NOT EXISTS dead_letter_queue (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), lead_id uuid REFERENCES leads(id) ON DELETE SET NULL,
 workflow text NOT NULL, operation text NOT NULL, payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 error_type text NOT NULL, error_message text NOT NULL, attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
 status text NOT NULL DEFAULT 'pending', created_at timestamptz NOT NULL DEFAULT now(), reprocessed_at timestamptz
);

-- =============================================================================
-- Indexes
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_leads_phone_normalized ON leads (phone_normalized);
CREATE INDEX IF NOT EXISTS idx_leads_email_normalized ON leads (email_normalized);
CREATE INDEX IF NOT EXISTS idx_leads_final_status ON leads (final_status);
CREATE INDEX IF NOT EXISTS idx_leads_assigned_sales_rep_id ON leads (assigned_sales_rep_id);
CREATE INDEX IF NOT EXISTS idx_leads_processing_status ON leads (processing_status);
CREATE INDEX IF NOT EXISTS idx_lead_events_lead_id ON lead_events (lead_id);
CREATE INDEX IF NOT EXISTS idx_lead_events_event_type_created_at ON lead_events (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expires_at ON idempotency_keys (expires_at);
CREATE INDEX IF NOT EXISTS idx_duplicate_decisions_candidate_lead_id ON duplicate_decisions (candidate_lead_id);
CREATE INDEX IF NOT EXISTS idx_duplicate_decisions_matched_lead_id ON duplicate_decisions (matched_lead_id);
CREATE INDEX IF NOT EXISTS idx_followups_scheduled_at ON followups (scheduled_at);
CREATE INDEX IF NOT EXISTS idx_followups_lead_id ON followups (lead_id);
CREATE INDEX IF NOT EXISTS idx_manager_approvals_lead_id ON manager_approvals (lead_id);
CREATE INDEX IF NOT EXISTS idx_bookings_lead_id ON bookings (lead_id);
CREATE INDEX IF NOT EXISTS idx_dead_letter_queue_status_created_at ON dead_letter_queue (status, created_at);
CREATE INDEX IF NOT EXISTS idx_dead_letter_queue_lead_id ON dead_letter_queue (lead_id);

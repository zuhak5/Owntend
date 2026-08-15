-- Migration: 20260815000003_points_monetization.sql
-- Description: Server-Authoritative Points Wallets, Ledger, SSV Reward Settlement, and Gated Creation RPCs

BEGIN;

CREATE SCHEMA IF NOT EXISTS owntend_monetization_private;
REVOKE ALL ON SCHEMA owntend_monetization_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA owntend_monetization_private TO authenticated, service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(
  p_user_id UUID,
  p_plan_id TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT auth.uid() = p_user_id
    AND EXISTS (
      SELECT 1
      FROM public.maintenance_plans
      WHERE user_id = p_user_id AND id = p_plan_id
    );
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(UUID, TEXT)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.can_reconcile_maintenance_plan(UUID, TEXT)
TO authenticated;

DROP POLICY IF EXISTS maintenance_plans_insert_own ON public.maintenance_plans;
CREATE POLICY maintenance_plans_insert_own ON public.maintenance_plans
FOR INSERT TO authenticated
WITH CHECK (
  auth.uid() = user_id
  AND (
    owntend_monetization_private.can_reconcile_maintenance_plan(user_id, id)
    OR current_setting('owntend.completion_plan_insert', true) = 'true'
  )
);

-- 1. Monetization Tables

CREATE TABLE IF NOT EXISTS public.point_wallets (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  balance INTEGER NOT NULL DEFAULT 7 CONSTRAINT point_wallets_balance_check CHECK (balance BETWEEN 0 AND 1000),
  reward_time_zone TEXT NOT NULL DEFAULT 'UTC' CHECK (
    CHAR_LENGTH(reward_time_zone) BETWEEN 1 AND 100
  ),
  reward_time_zone_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.point_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount <> 0),
  balance_before INTEGER NOT NULL CONSTRAINT point_transactions_balance_before_check CHECK (balance_before BETWEEN 0 AND 1000),
  balance_after INTEGER NOT NULL CONSTRAINT point_transactions_balance_after_check CHECK (
    balance_after BETWEEN 0 AND 1000
    AND balance_after = balance_before + amount
  ),
  transaction_type TEXT NOT NULL CHECK (
    transaction_type IN (
      'initial_grant',
      'task_creation',
      'asset_creation',
      'rewarded_ad',
      'rewarded_interstitial',
      'refund',
      'admin_adjustment'
    )
  ),
  reference_id TEXT,
  idempotency_key TEXT NOT NULL CHECK (CHAR_LENGTH(idempotency_key) BETWEEN 1 AND 200),
  reward_day DATE,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS point_transactions_daily_reward_uidx
  ON public.point_transactions (user_id, reward_day)
  WHERE transaction_type = 'rewarded_interstitial'
    AND reward_day IS NOT NULL;

CREATE INDEX IF NOT EXISTS point_transactions_user_created_idx
  ON public.point_transactions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS points_transactions_user_id_idx
  ON public.point_transactions (user_id);

CREATE TABLE IF NOT EXISTS public.reward_claim_requests (
  claim_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reward_type TEXT NOT NULL CHECK (
    reward_type IN ('rewarded_ad', 'rewarded_interstitial')
  ),
  ad_unit_id TEXT NOT NULL CHECK (CHAR_LENGTH(ad_unit_id) BETWEEN 1 AND 120),
  reward_amount INTEGER NOT NULL CHECK (reward_amount IN (1, 2)),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (
    status IN ('pending', 'processed', 'expired', 'rejected')
  ),
  reward_day DATE NOT NULL DEFAULT (timezone('utc', NOW()))::date,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ,
  rejection_reason TEXT CHECK (
    rejection_reason IS NULL OR CHAR_LENGTH(rejection_reason) <= 200
  )
);

CREATE INDEX IF NOT EXISTS reward_claim_requests_pending_idx
  ON public.reward_claim_requests (user_id, status, expires_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS reward_claim_requests_user_created_idx
  ON public.reward_claim_requests (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.ad_reward_claims (
  transaction_id TEXT PRIMARY KEY CHECK (CHAR_LENGTH(transaction_id) BETWEEN 1 AND 200),
  claim_id UUID NOT NULL UNIQUE REFERENCES public.reward_claim_requests(claim_id),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reward_type TEXT NOT NULL CHECK (
    reward_type IN ('rewarded_ad', 'rewarded_interstitial')
  ),
  ad_unit_id TEXT NOT NULL,
  reward_amount INTEGER NOT NULL CHECK (reward_amount IN (1, 2)),
  reward_day DATE NOT NULL,
  google_timestamp TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS ad_reward_claims_user_id_idx
  ON public.ad_reward_claims (user_id);

CREATE TABLE IF NOT EXISTS public.creation_point_operations (
  operation_id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  entity_type TEXT NOT NULL CHECK (entity_type IN ('task', 'asset')),
  entity_id TEXT NOT NULL CHECK (CHAR_LENGTH(entity_id) BETWEEN 1 AND 200),
  charged_amount INTEGER NOT NULL CHECK (charged_amount IN (0, 1)),
  request_hash TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, entity_type, entity_id)
);

CREATE INDEX IF NOT EXISTS creation_point_operations_user_id_idx
  ON public.creation_point_operations (user_id);

CREATE TABLE IF NOT EXISTS public.monetization_config (
  singleton BOOLEAN PRIMARY KEY DEFAULT true CHECK (singleton),
  ads_enabled BOOLEAN NOT NULL DEFAULT true,
  native_ads_enabled BOOLEAN NOT NULL DEFAULT true,
  interstitial_ads_enabled BOOLEAN NOT NULL DEFAULT true,
  rewarded_ads_enabled BOOLEAN NOT NULL DEFAULT true,
  rewarded_interstitial_enabled BOOLEAN NOT NULL DEFAULT true,
  points_enabled BOOLEAN NOT NULL DEFAULT true,
  emergency_free_creation_mode BOOLEAN NOT NULL DEFAULT false,
  wallet_cap INTEGER NOT NULL DEFAULT 20,
  interstitial_cooldown_seconds INTEGER NOT NULL DEFAULT 180 CHECK (
    interstitial_cooldown_seconds BETWEEN 0 AND 86400
  ),
  rapid_completion_window_seconds INTEGER NOT NULL DEFAULT 60 CHECK (
    rapid_completion_window_seconds BETWEEN 0 AND 3600
  ),
  reward_claim_cooldown_seconds INTEGER NOT NULL DEFAULT 45 CHECK (
    reward_claim_cooldown_seconds BETWEEN 0 AND 3600
  ),
  interstitial_session_cap INTEGER NOT NULL DEFAULT 3 CHECK (
    interstitial_session_cap BETWEEN 0 AND 20
  ),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.monetization_config (singleton) VALUES (true)
ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.monetization_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_name TEXT NOT NULL CHECK (
    event_name IN (
      'ad_native_impression',
      'ad_native_click',
      'ad_interstitial_shown',
      'ad_rewarded_watched',
      'point_shortage_encountered',
      'points_debited'
    )
  ),
  properties JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS monetization_events_user_id_idx
  ON public.monetization_events (user_id);

-- 2. Row Level Security on Monetization Tables

ALTER TABLE public.point_wallets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.point_wallets FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.point_wallets TO authenticated;
GRANT ALL ON TABLE public.point_wallets TO service_role;

DROP POLICY IF EXISTS point_wallets_select_own ON public.point_wallets;
CREATE POLICY point_wallets_select_own ON public.point_wallets
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

ALTER TABLE public.point_transactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.point_transactions FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.point_transactions TO authenticated;
GRANT ALL ON TABLE public.point_transactions TO service_role;

DROP POLICY IF EXISTS point_transactions_select_own ON public.point_transactions;
CREATE POLICY point_transactions_select_own ON public.point_transactions
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

ALTER TABLE public.reward_claim_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.reward_claim_requests FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.reward_claim_requests TO authenticated;
GRANT ALL ON TABLE public.reward_claim_requests TO service_role;

DROP POLICY IF EXISTS reward_claim_requests_select_own ON public.reward_claim_requests;
CREATE POLICY reward_claim_requests_select_own ON public.reward_claim_requests
FOR SELECT TO authenticated
USING (auth.uid() = user_id);

ALTER TABLE public.ad_reward_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ad_reward_claims FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.ad_reward_claims TO service_role;

DROP POLICY IF EXISTS ad_reward_claims_service_role_all ON public.ad_reward_claims;
CREATE POLICY ad_reward_claims_service_role_all ON public.ad_reward_claims
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

ALTER TABLE public.creation_point_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.creation_point_operations FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.creation_point_operations TO service_role;

DROP POLICY IF EXISTS creation_point_operations_service_role_all ON public.creation_point_operations;
CREATE POLICY creation_point_operations_service_role_all ON public.creation_point_operations
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

ALTER TABLE public.monetization_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.monetization_config FROM PUBLIC, anon;
GRANT SELECT ON TABLE public.monetization_config TO authenticated;
GRANT ALL ON TABLE public.monetization_config TO service_role;

DROP POLICY IF EXISTS monetization_config_select_authenticated ON public.monetization_config;
CREATE POLICY monetization_config_select_authenticated ON public.monetization_config
FOR SELECT TO authenticated
USING (true);

ALTER TABLE public.monetization_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.monetization_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.monetization_events TO service_role;

DROP POLICY IF EXISTS monetization_events_service_role_all ON public.monetization_events;
CREATE POLICY monetization_events_service_role_all ON public.monetization_events
FOR ALL TO service_role
USING (true)
WITH CHECK (true);

-- 3. Authorization Helper Functions

CREATE OR REPLACE FUNCTION owntend_monetization_private.is_authorized_point_creation_impl(
  p_user_id UUID,
  p_entity_type TEXT,
  p_entity_id TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT (SELECT auth.uid()) = p_user_id
    AND (
      EXISTS (
        SELECT 1
        FROM public.creation_point_operations
        WHERE user_id = p_user_id
          AND entity_type = p_entity_type
          AND entity_id = p_entity_id
      )
      OR (
        p_entity_type = 'asset'
        AND EXISTS (
          SELECT 1 FROM public.assets
          WHERE user_id = p_user_id AND id = p_entity_id
        )
      )
      OR (
        p_entity_type = 'task'
        AND EXISTS (
          SELECT 1 FROM public.maintenance_plans
          WHERE user_id = p_user_id AND id = p_entity_id
        )
      )
    );
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.is_authorized_point_creation_impl(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.is_authorized_point_creation_impl(UUID, TEXT, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_authorized_point_creation(
  p_user_id UUID,
  p_entity_type TEXT,
  p_entity_id TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.is_authorized_point_creation_impl(
    p_user_id,
    p_entity_type,
    p_entity_id
  );
$$;

REVOKE ALL ON FUNCTION public.is_authorized_point_creation(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_authorized_point_creation(UUID, TEXT, TEXT) TO authenticated;

-- Ensure auth.users trigger initializes a point wallet for new users
CREATE OR REPLACE FUNCTION owntend_private.initialize_point_wallet_for_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.point_wallets (user_id, balance)
  VALUES (NEW.id, 7)
  ON CONFLICT (user_id) DO NOTHING;

  INSERT INTO public.point_transactions (
    user_id, amount, balance_before, balance_after,
    transaction_type, idempotency_key, metadata
  ) VALUES (
    NEW.id, 7, 0, 7,
    'initial_grant', 'initial_grant:' || NEW.id::text,
    jsonb_build_object('grant_type', 'signup_welcome')
  ) ON CONFLICT (user_id, idempotency_key) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS initialize_point_wallet_for_user ON auth.users;
CREATE TRIGGER initialize_point_wallet_for_user
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION owntend_private.initialize_point_wallet_for_user();

-- 4. Monetization RPCs

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(
  p_operation JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  operation_uuid UUID;
  plan_json JSONB;
  metadata_json JSONB;
  plan_id TEXT;
  target_asset_id TEXT;
  current_balance INTEGER;
  next_balance INTEGER;
  charge INTEGER := 1;
  is_safety BOOLEAN;
  config_row public.monetization_config%ROWTYPE;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash TEXT;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL
    OR jsonb_typeof(p_operation) <> 'object'
    OR pg_column_size(p_operation) > 65536
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION';
  END IF;

  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;

  plan_json := p_operation->'plan';
  metadata_json := COALESCE(p_operation->'metadata', '{}'::jsonb);
  IF jsonb_typeof(plan_json) <> 'object'
    OR jsonb_typeof(metadata_json) <> 'object'
    OR (
      metadata_json ? 'required_materials'
      AND jsonb_typeof(metadata_json -> 'required_materials') <> 'array'
    )
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;

  plan_id := NULLIF(BTRIM(plan_json->>'id'), '');
  target_asset_id := NULLIF(BTRIM(plan_json->>'asset_id'), '');
  IF plan_id IS NULL OR target_asset_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
  END IF;

  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      caller_id::text || ':task_op:' || operation_uuid::text,
      0
    )
  );

  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
      OR existing_operation.entity_type <> 'task'
      OR existing_operation.entity_id <> plan_id
      OR (existing_operation.request_hash IS NOT NULL AND existing_operation.request_hash <> v_request_hash)
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT balance INTO current_balance
    FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'task_id', plan_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true
    );
  END IF;

  SELECT (assets.asset_type = 'safety' OR assets.category_id = 'category_safety')
  INTO is_safety
  FROM public.assets
  WHERE assets.user_id = caller_id
    AND assets.id = target_asset_id
    AND assets.archived_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ASSET_NOT_FOUND';
  END IF;

  SELECT * INTO config_row
  FROM public.monetization_config WHERE singleton = true;
  IF NOT config_row.points_enabled
    OR config_row.emergency_free_creation_mode
    OR is_safety
  THEN
    charge := 0;
  END IF;

  SELECT balance INTO current_balance
  FROM public.point_wallets
  WHERE user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;

  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'task_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true
    );
  END IF;

  IF charge = 1 AND current_balance < 1 THEN
    RETURN jsonb_build_object(
      'status', 'insufficient_points',
      'task_id', null,
      'balance', current_balance,
      'charged', 0,
      'already_processed', false
    );
  END IF;
  next_balance := current_balance - charge;

  INSERT INTO public.maintenance_plans (
    user_id,
    id,
    asset_id,
    title,
    description,
    interval_count,
    interval_unit,
    priority,
    next_due_date,
    reminder_days_before,
    health_group,
    created_at,
    updated_at,
    archived_at,
    revision,
    is_enabled
  ) VALUES (
    caller_id,
    plan_id,
    target_asset_id,
    BTRIM(plan_json->>'title'),
    COALESCE(
      NULLIF(BTRIM(plan_json->>'description'), ''),
      NULLIF(BTRIM(plan_json->>'instructions'), '')
    ),
    COALESCE((plan_json->>'interval_count')::integer, (plan_json->>'recurrence_interval')::integer, 1),
    COALESCE(plan_json->>'interval_unit', plan_json->>'recurrence_unit', 'months'),
    COALESCE(plan_json->>'priority', 'medium'),
    (plan_json->>'next_due_date')::timestamptz,
    COALESCE((plan_json->>'reminder_days_before')::integer, 0),
    CASE WHEN is_safety THEN 'safety' ELSE plan_json->>'health_group' END,
    NOW(),
    NOW(),
    NULL,
    1,
    COALESCE((plan_json->>'is_enabled')::boolean, true)
  );

  IF metadata_json <> '{}'::jsonb THEN
    INSERT INTO public.maintenance_plan_metadata (
      user_id,
      plan_id,
      task_type,
      location_label,
      estimated_duration_minutes,
      required_materials_json,
      reminder_recommendation,
      sort_order,
      created_at,
      updated_at,
      revision
    ) VALUES (
      caller_id,
      plan_id,
      NULLIF(BTRIM(metadata_json->>'task_type'), ''),
      NULLIF(BTRIM(metadata_json->>'location_label'), ''),
      (metadata_json->>'estimated_duration_minutes')::integer,
      COALESCE(metadata_json->>'required_materials_json', (metadata_json->'required_materials')::text, '[]'),
      NULLIF(BTRIM(metadata_json->>'reminder_recommendation'), ''),
      COALESCE((metadata_json->>'sort_order')::integer, 0),
      NOW(),
      NOW(),
      1
    );
  END IF;

  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount, request_hash
  ) VALUES (operation_uuid, caller_id, 'task', plan_id, charge, v_request_hash);

  IF charge = 1 THEN
    UPDATE public.point_wallets
    SET balance = next_balance, updated_at = NOW()
    WHERE user_id = caller_id;

    INSERT INTO public.point_transactions (
      user_id,
      amount,
      balance_before,
      balance_after,
      transaction_type,
      reference_id,
      idempotency_key,
      metadata
    ) VALUES (
      caller_id,
      -1,
      current_balance,
      next_balance,
      'task_creation',
      plan_id,
      'create-task:' || operation_uuid::text,
      jsonb_build_object('asset_id', target_asset_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'task_id', plan_id,
    'balance', next_balance,
    'charged', charge,
    'already_processed', false
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TASK_PAYLOAD';
END;
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_task_with_point_debit_impl(JSONB) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_task_with_point_debit(p_operation JSONB)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.create_task_with_point_debit_impl(p_operation);
$$;

REVOKE ALL ON FUNCTION public.create_task_with_point_debit(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_task_with_point_debit(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(
  p_operation JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  operation_uuid UUID;
  asset_json JSONB;
  details_json JSONB;
  plans_json JSONB;
  plan_json JSONB;
  metadata_json JSONB;
  asset_id TEXT;
  asset_kind TEXT;
  category_health_group TEXT;
  current_balance INTEGER;
  existing_operation public.creation_point_operations%ROWTYPE;
  v_request_hash TEXT;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_operation IS NULL
    OR jsonb_typeof(p_operation) <> 'object'
    OR pg_column_size(p_operation) > 262144
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION';
  END IF;

  BEGIN
    operation_uuid := (p_operation->>'operation_id')::uuid;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END;

  asset_json := p_operation->'asset';
  details_json := COALESCE(p_operation->'details', '{}'::jsonb);
  plans_json := COALESCE(p_operation->'initial_plans', '[]'::jsonb);
  IF jsonb_typeof(asset_json) <> 'object'
    OR jsonb_typeof(details_json) <> 'object'
    OR jsonb_typeof(plans_json) <> 'array'
    OR jsonb_array_length(plans_json) > 50
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;

  asset_id := NULLIF(BTRIM(asset_json->>'id'), '');
  asset_kind := asset_json->>'asset_type';
  IF asset_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
  END IF;

  v_request_hash := encode(extensions.digest(p_operation::text::bytea, 'sha256'), 'hex');

  -- Advisory lock scoped to caller and operation UUID
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      caller_id::text || ':asset_op:' || operation_uuid::text,
      0
    )
  );

  -- Check for existing operation for idempotency
  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
      OR existing_operation.entity_type <> 'asset'
      OR existing_operation.entity_id <> asset_id
      OR (existing_operation.request_hash IS NOT NULL AND existing_operation.request_hash <> v_request_hash)
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    SELECT COALESCE(balance, 0) INTO current_balance
    FROM public.point_wallets WHERE user_id = caller_id;
    RETURN jsonb_build_object(
      'asset_id', asset_id,
      'balance', COALESCE(current_balance, 0),
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'asset', (
        SELECT to_jsonb(a) FROM public.assets a
        WHERE a.user_id = caller_id AND a.id = asset_id
      )
    );
  END IF;

  IF (asset_json->>'room_id') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.rooms
    WHERE user_id = caller_id
      AND id = asset_json->>'room_id'
      AND archived_at IS NULL
  ) THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'ROOM_NOT_FOUND';
  END IF;

  category_health_group := CASE asset_json->>'category_id'
    WHEN 'category_safety' THEN 'safety'
    WHEN 'category_pets' THEN 'pets'
    WHEN 'category_appliances' THEN 'appliances'
    WHEN 'category_plants' THEN 'plants'
    WHEN 'category_cleaning' THEN 'cleaning'
    WHEN 'category_general' THEN 'other'
    ELSE NULL
  END;
  IF category_health_group IS NULL AND asset_json->>'category_id' IS NOT NULL THEN
    RAISE EXCEPTION USING errcode = '23503', message = 'CATEGORY_NOT_FOUND';
  END IF;

  -- Read current balance (if wallet exists, otherwise default 0).
  -- Note: In the V1 economy, asset creation is always free (0 points),
  -- so no balance sufficiency check or wallet row locking is required.
  SELECT balance INTO current_balance
  FROM public.point_wallets
  WHERE user_id = caller_id;
  IF NOT FOUND THEN
    current_balance := 0;
  END IF;

  -- Re-verify operation idempotency
  SELECT * INTO existing_operation
  FROM public.creation_point_operations
  WHERE operation_id = operation_uuid;
  IF FOUND THEN
    IF existing_operation.user_id <> caller_id
      OR existing_operation.entity_type <> 'asset'
      OR existing_operation.entity_id <> asset_id
      OR (existing_operation.request_hash IS NOT NULL AND existing_operation.request_hash <> v_request_hash)
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
    END IF;
    RETURN jsonb_build_object(
      'asset_id', existing_operation.entity_id,
      'balance', current_balance,
      'charged', existing_operation.charged_amount,
      'already_processed', true,
      'asset', (
        SELECT to_jsonb(a) FROM public.assets a
        WHERE a.user_id = caller_id AND a.id = existing_operation.entity_id
      )
    );
  END IF;

  -- Insert asset
  INSERT INTO public.assets (
    user_id, id, room_id, category_id, name,
    purchase_date, notes, created_at, updated_at,
    archived_at, revision, asset_type
  ) VALUES (
    caller_id, asset_id, asset_json->>'room_id', asset_json->>'category_id',
    BTRIM(asset_json->>'name'),
    (asset_json->>'purchase_date')::date,
    NULLIF(BTRIM(asset_json->>'notes'), ''),
    NOW(), NOW(), NULL, 1, COALESCE(asset_kind, 'general')
  );

  -- Insert specialized details if present
  IF details_json <> '{}'::jsonb THEN
    IF asset_kind = 'device' THEN
      INSERT INTO public.device_details (
        user_id, asset_id, brand, model, serial_number, power_source,
        warranty_until, manual_url, consumable, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'brand'), ''),
        NULLIF(BTRIM(details_json->>'model'), ''),
        NULLIF(BTRIM(details_json->>'serial_number'), ''),
        NULLIF(BTRIM(details_json->>'power_source'), ''),
        (details_json->>'warranty_until')::date,
        NULLIF(BTRIM(details_json->>'manual_url'), ''),
        COALESCE((details_json->>'consumable')::boolean, false),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'pet' THEN
      INSERT INTO public.pet_details (
        user_id, asset_id, species, breed, birth_date, microchip_id,
        vet_name, vet_phone, feeding_notes, medical_notes, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'species'), ''),
        NULLIF(BTRIM(details_json->>'breed'), ''),
        (details_json->>'birth_date')::date,
        NULLIF(BTRIM(details_json->>'microchip_id'), ''),
        NULLIF(BTRIM(details_json->>'vet_name'), ''),
        NULLIF(BTRIM(details_json->>'vet_phone'), ''),
        NULLIF(BTRIM(details_json->>'feeding_notes'), ''),
        NULLIF(BTRIM(details_json->>'medical_notes'), ''),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'plant' THEN
      INSERT INTO public.plant_details (
        user_id, asset_id, species, sunlight, watering_interval_days,
        pot_size, last_repotted_at, toxicity_notes, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'species'), ''),
        NULLIF(BTRIM(details_json->>'sunlight'), ''),
        (details_json->>'watering_interval_days')::integer,
        NULLIF(BTRIM(details_json->>'pot_size'), ''),
        (details_json->>'last_repotted_at')::timestamptz,
        NULLIF(BTRIM(details_json->>'toxicity_notes'), ''),
        NOW(), NOW(), 1
      );
    ELSIF asset_kind = 'safety' THEN
      INSERT INTO public.safety_details (
        user_id, asset_id, safety_type, installed_at, expires_at,
        battery_type, test_interval_days, created_at, updated_at, revision
      ) VALUES (
        caller_id, asset_id,
        NULLIF(BTRIM(details_json->>'safety_type'), ''),
        (details_json->>'installed_at')::timestamptz,
        (details_json->>'expires_at')::timestamptz,
        NULLIF(BTRIM(details_json->>'battery_type'), ''),
        (details_json->>'test_interval_days')::integer,
        NOW(), NOW(), 1
      );
    END IF;
  END IF;

  -- Insert bundled initial maintenance plans (always 0 points)
  FOR plan_json IN SELECT * FROM jsonb_array_elements(plans_json) LOOP
    metadata_json := COALESCE(plan_json->'metadata', '{}'::jsonb);
    INSERT INTO public.maintenance_plans (
      user_id, id, asset_id, title, description, interval_count,
      interval_unit, priority, next_due_date, reminder_days_before,
      health_group, created_at, updated_at, archived_at, revision, is_enabled
    ) VALUES (
      caller_id, plan_json->>'id', asset_id, BTRIM(plan_json->>'title'),
      COALESCE(
        NULLIF(BTRIM(plan_json->>'description'), ''),
        NULLIF(BTRIM(plan_json->>'instructions'), '')
      ),
      COALESCE((plan_json->>'interval_count')::integer, (plan_json->>'recurrence_interval')::integer, 1),
      COALESCE(plan_json->>'interval_unit', plan_json->>'recurrence_unit', 'months'),
      COALESCE(plan_json->>'priority', 'medium'),
      (plan_json->>'next_due_date')::timestamptz,
      COALESCE((plan_json->>'reminder_days_before')::integer, 0),
      CASE WHEN category_health_group = 'safety' THEN 'safety' ELSE plan_json->>'health_group' END,
      NOW(), NOW(), NULL, 1, COALESCE((plan_json->>'is_enabled')::boolean, true)
    );
    IF metadata_json <> '{}'::jsonb THEN
      INSERT INTO public.maintenance_plan_metadata (
        user_id, plan_id, task_type, location_label, estimated_duration_minutes,
        required_materials_json, reminder_recommendation,
        sort_order, created_at, updated_at, revision
      ) VALUES (
        caller_id, plan_json->>'id',
        NULLIF(BTRIM(metadata_json->>'task_type'), ''),
        NULLIF(BTRIM(metadata_json->>'location_label'), ''),
        (metadata_json->>'estimated_duration_minutes')::integer,
        COALESCE(metadata_json->>'required_materials_json', (metadata_json->'required_materials')::text, '[]'),
        NULLIF(BTRIM(metadata_json->>'reminder_recommendation'), ''),
        COALESCE((metadata_json->>'sort_order')::integer, 0),
        NOW(), NOW(), 1
      );
    END IF;
  END LOOP;

  -- Record creation operation with charged_amount = 0
  INSERT INTO public.creation_point_operations (
    operation_id, user_id, entity_type, entity_id, charged_amount, request_hash
  ) VALUES (operation_uuid, caller_id, 'asset', asset_id, 0, v_request_hash);

  -- Return success with charged = 0 and unchanged balance
  RETURN jsonb_build_object(
    'asset_id', asset_id,
    'balance', current_balance,
    'charged', 0,
    'already_processed', false,
    'asset', (
      SELECT to_jsonb(a) FROM public.assets a
      WHERE a.user_id = caller_id AND a.id = asset_id
    )
  );
EXCEPTION
  WHEN check_violation OR not_null_violation OR invalid_text_representation THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_ASSET_PAYLOAD';
END;
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_asset_with_point_debit_impl(JSONB) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_asset_with_point_debit(p_operation JSONB)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.create_asset_with_point_debit_impl(p_operation);
$$;

REVOKE ALL ON FUNCTION public.create_asset_with_point_debit(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_asset_with_point_debit(JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION owntend_monetization_private.create_reward_claim_request_impl(
  p_reward_type TEXT,
  p_time_zone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  wallet_row public.point_wallets%ROWTYPE;
  config_row public.monetization_config%ROWTYPE;
  reward_amount INTEGER;
  ad_unit_id TEXT;
  requested_time_zone TEXT;
  local_reward_day DATE;
  claim_row public.reward_claim_requests%ROWTYPE;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_reward_type NOT IN ('rewarded_ad', 'rewarded_interstitial') THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REWARD_TYPE';
  END IF;

  SELECT * INTO config_row
  FROM public.monetization_config WHERE singleton = true;
  IF NOT config_row.ads_enabled OR NOT config_row.rewarded_ads_enabled
    OR (p_reward_type = 'rewarded_interstitial'
      AND NOT config_row.rewarded_interstitial_enabled)
  THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'REWARDS_DISABLED';
  END IF;

  reward_amount := case when p_reward_type = 'rewarded_ad' then 1 else 2 end;
  ad_unit_id := CASE
    WHEN p_reward_type = 'rewarded_ad'
      THEN 'ca-app-pub-5274007212820203/4541482404'
    ELSE 'ca-app-pub-5274007212820203/7295784043'
  END;

  SELECT * INTO wallet_row
  FROM public.point_wallets WHERE user_id = caller_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_NOT_FOUND';
  END IF;

  requested_time_zone := NULLIF(BTRIM(p_time_zone), '');
  IF requested_time_zone IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names
      WHERE name = requested_time_zone
    )
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_TIME_ZONE';
  END IF;
  IF requested_time_zone IS NOT NULL
    AND requested_time_zone <> wallet_row.reward_time_zone
  THEN
    IF EXISTS (
      SELECT 1 FROM public.point_transactions
      WHERE user_id = caller_id
        AND transaction_type IN ('rewarded_ad', 'rewarded_interstitial')
    ) AND wallet_row.reward_time_zone_updated_at > NOW() - INTERVAL '30 days'
    THEN
      RAISE EXCEPTION USING errcode = 'P0001', message = 'TIME_ZONE_CHANGE_COOLDOWN';
    END IF;
    UPDATE public.point_wallets
    SET reward_time_zone = requested_time_zone,
        reward_time_zone_updated_at = NOW(),
        updated_at = NOW()
    WHERE user_id = caller_id;
    wallet_row.reward_time_zone := requested_time_zone;
  END IF;
  local_reward_day := (timezone(wallet_row.reward_time_zone, NOW()))::date;

  UPDATE public.reward_claim_requests
  SET status = 'expired', rejection_reason = 'expired'
  WHERE user_id = caller_id AND status = 'pending' AND expires_at <= NOW();

  IF wallet_row.balance + reward_amount > config_row.wallet_cap THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'WALLET_CAP_REACHED';
  END IF;
  IF p_reward_type = 'rewarded_interstitial' AND EXISTS (
    SELECT 1 FROM public.point_transactions
    WHERE user_id = caller_id
      AND transaction_type = 'rewarded_interstitial'
      AND reward_day = local_reward_day
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'REWARD_ALREADY_CLAIMED';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.reward_claim_requests
    WHERE user_id = caller_id
      AND created_at > NOW() - make_interval(
        secs => config_row.reward_claim_cooldown_seconds
      )
  ) THEN
    RAISE EXCEPTION USING errcode = 'P0001', message = 'REWARD_COOLDOWN';
  END IF;

  INSERT INTO public.reward_claim_requests (
    user_id, reward_type, ad_unit_id, reward_amount, reward_day
  ) VALUES (
    caller_id, p_reward_type, ad_unit_id, reward_amount, local_reward_day
  ) RETURNING * INTO claim_row;

  RETURN jsonb_build_object(
    'claim_id', claim_row.claim_id,
    'user_id', caller_id,
    'custom_data', claim_row.claim_id::text,
    'reward_type', claim_row.reward_type,
    'reward_amount', claim_row.reward_amount,
    'ad_unit_id', claim_row.ad_unit_id,
    'expires_at', claim_row.expires_at,
    'reward_day', claim_row.reward_day,
    'time_zone', wallet_row.reward_time_zone
  );
END;
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.create_reward_claim_request_impl(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.create_reward_claim_request_impl(TEXT, TEXT) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_reward_claim_request(
  p_reward_type TEXT,
  p_time_zone TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.create_reward_claim_request_impl(
    p_reward_type,
    p_time_zone
  );
$$;

REVOKE ALL ON FUNCTION public.create_reward_claim_request(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_reward_claim_request(TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.process_admob_ssv_reward(
  p_transaction_id TEXT,
  p_claim_id UUID,
  p_user_id UUID,
  p_ad_unit_id TEXT,
  p_reward_amount INTEGER,
  p_reward_item TEXT,
  p_google_timestamp TIMESTAMPTZ
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  claim_row public.reward_claim_requests%ROWTYPE;
  wallet_row public.point_wallets%ROWTYPE;
  config_row public.monetization_config%ROWTYPE;
  new_balance INTEGER;
  existing_claim public.ad_reward_claims%ROWTYPE;
BEGIN
  IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'SERVICE_ROLE_REQUIRED';
  END IF;

  IF p_transaction_id IS NULL
    OR CHAR_LENGTH(p_transaction_id) NOT BETWEEN 1 AND 200
    OR p_transaction_id ~ '[[:cntrl:]]'
    OR p_claim_id IS NULL
    OR p_user_id IS NULL
    OR p_ad_unit_id IS NULL
    OR p_reward_amount IS NULL
    OR p_reward_item IS DISTINCT FROM 'points'
    OR p_google_timestamp IS NULL
    OR p_google_timestamp > NOW() + INTERVAL '5 minutes'
    OR p_ad_unit_id NOT IN (
      'ca-app-pub-5274007212820203/4541482404',
      'ca-app-pub-5274007212820203/7295784043'
    )
    OR (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/4541482404'
      AND p_reward_amount <> 1
    )
    OR (
      p_ad_unit_id = 'ca-app-pub-5274007212820203/7295784043'
      AND p_reward_amount <> 2
    )
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_SSV_PAYLOAD';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_transaction_id, 0)
  );

  SELECT * INTO existing_claim
  FROM public.ad_reward_claims
  WHERE transaction_id = p_transaction_id;
  IF FOUND THEN
    IF existing_claim.claim_id IS DISTINCT FROM p_claim_id
      OR existing_claim.user_id IS DISTINCT FROM p_user_id
      OR existing_claim.ad_unit_id IS DISTINCT FROM p_ad_unit_id
      OR existing_claim.reward_amount IS DISTINCT FROM p_reward_amount
      OR existing_claim.google_timestamp IS DISTINCT FROM p_google_timestamp
    THEN
      RAISE EXCEPTION USING errcode = '23505', message = 'TRANSACTION_ID_REUSED';
    END IF;

    SELECT balance INTO new_balance
    FROM public.point_wallets
    WHERE user_id = p_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
    END IF;
    RETURN jsonb_build_object(
      'credited', true,
      'duplicate', true,
      'balance', new_balance,
      'reward_amount', existing_claim.reward_amount
    );
  END IF;

  IF p_google_timestamp < NOW() - INTERVAL '20 minutes' THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'SSV_TIMESTAMP_EXPIRED';
  END IF;

  SELECT * INTO claim_row
  FROM public.reward_claim_requests
  WHERE claim_id = p_claim_id
  FOR UPDATE;
  IF NOT FOUND
    OR claim_row.user_id IS DISTINCT FROM p_user_id
    OR claim_row.status IS DISTINCT FROM 'pending'
    OR claim_row.expires_at <= NOW()
    OR claim_row.ad_unit_id IS DISTINCT FROM p_ad_unit_id
    OR claim_row.reward_amount IS DISTINCT FROM p_reward_amount
    OR p_google_timestamp < claim_row.created_at - INTERVAL '5 minutes'
    OR p_google_timestamp > claim_row.expires_at + INTERVAL '5 minutes'
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_REWARD_CLAIM';
  END IF;

  SELECT * INTO wallet_row
  FROM public.point_wallets
  WHERE user_id = p_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
  END IF;

  SELECT * INTO config_row
  FROM public.monetization_config
  WHERE singleton = true;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING message = 'SSV_SERVER_STATE_INVALID';
  END IF;

  IF wallet_row.balance + claim_row.reward_amount > config_row.wallet_cap THEN
    UPDATE public.reward_claim_requests
    SET status = 'rejected', processed_at = NOW(),
        rejection_reason = 'wallet_cap_reached'
    WHERE claim_id = p_claim_id;
    RETURN jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'wallet_cap_reached'
    );
  END IF;

  IF claim_row.reward_type = 'rewarded_interstitial' AND EXISTS (
    SELECT 1
    FROM public.point_transactions
    WHERE user_id = p_user_id
      AND transaction_type = 'rewarded_interstitial'
      AND reward_day = claim_row.reward_day
  ) THEN
    UPDATE public.reward_claim_requests
    SET status = 'rejected', processed_at = NOW(),
        rejection_reason = 'daily_reward_already_claimed'
    WHERE claim_id = p_claim_id;
    RETURN jsonb_build_object(
      'credited', false,
      'duplicate', false,
      'balance', wallet_row.balance,
      'reason', 'daily_reward_already_claimed'
    );
  END IF;

  new_balance := wallet_row.balance + claim_row.reward_amount;
  INSERT INTO public.ad_reward_claims (
    transaction_id, claim_id, user_id, reward_type, ad_unit_id,
    reward_amount, reward_day, google_timestamp
  ) VALUES (
    p_transaction_id, p_claim_id, p_user_id, claim_row.reward_type,
    p_ad_unit_id, claim_row.reward_amount, claim_row.reward_day,
    p_google_timestamp
  );

  UPDATE public.point_wallets
  SET balance = new_balance, updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO public.point_transactions (
    user_id, amount, balance_before, balance_after, transaction_type,
    reference_id, idempotency_key, reward_day, metadata
  ) VALUES (
    p_user_id,
    claim_row.reward_amount,
    wallet_row.balance,
    new_balance,
    claim_row.reward_type,
    p_transaction_id,
    'ssv:' || p_transaction_id,
    claim_row.reward_day,
    jsonb_build_object(
      'claim_id', p_claim_id,
      'ad_unit_id', p_ad_unit_id,
      'google_timestamp', p_google_timestamp
    )
  );

  UPDATE public.reward_claim_requests
  SET status = 'processed', processed_at = NOW(), rejection_reason = NULL
  WHERE claim_id = p_claim_id;

  RETURN jsonb_build_object(
    'credited', true,
    'duplicate', false,
    'balance', new_balance,
    'reward_amount', claim_row.reward_amount
  );
END;
$$;

REVOKE ALL ON FUNCTION public.process_admob_ssv_reward(TEXT, UUID, UUID, TEXT, INTEGER, TEXT, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_admob_ssv_reward(TEXT, UUID, UUID, TEXT, INTEGER, TEXT, TIMESTAMPTZ) TO service_role;

CREATE OR REPLACE FUNCTION owntend_monetization_private.record_monetization_event_impl(
  p_event_name TEXT,
  p_properties JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;
  IF p_event_name NOT IN (
    'ad_native_impression',
    'ad_native_click',
    'ad_interstitial_shown',
    'ad_rewarded_watched',
    'point_shortage_encountered',
    'points_debited'
  ) OR p_properties IS NULL
    OR jsonb_typeof(p_properties) <> 'object'
    OR pg_column_size(p_properties) > 8192
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT';
  END IF;

  INSERT INTO public.monetization_events (user_id, event_name, properties)
  VALUES (caller_id, p_event_name, p_properties);
END;
$$;

REVOKE ALL ON FUNCTION owntend_monetization_private.record_monetization_event_impl(TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION owntend_monetization_private.record_monetization_event_impl(TEXT, JSONB) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.record_monetization_event(
  p_event_name TEXT,
  p_properties JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT owntend_monetization_private.record_monetization_event_impl(
    p_event_name,
    p_properties
  );
$$;

REVOKE ALL ON FUNCTION public.record_monetization_event(TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_monetization_event(TEXT, JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_charged_operation_status(
  p_operation_id UUID,
  p_request_hash TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_operation public.creation_point_operations%ROWTYPE;
  v_current_balance INTEGER;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '42501', message = 'AUTH_REQUIRED';
  END IF;

  IF p_operation_id IS NULL THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_OPERATION_ID';
  END IF;

  SELECT * INTO v_operation
  FROM public.creation_point_operations
  WHERE operation_id = p_operation_id;

  IF NOT FOUND OR v_operation.user_id <> v_caller_id THEN
    RETURN jsonb_build_object(
      'status', 'not_found',
      'capability_version', '1.1.0'
    );
  END IF;

  IF p_request_hash IS NOT NULL
    AND v_operation.request_hash IS NOT NULL
    AND p_request_hash <> v_operation.request_hash
  THEN
    RAISE EXCEPTION USING errcode = '23505', message = 'OPERATION_ID_REUSED';
  END IF;

  SELECT balance INTO v_current_balance
  FROM public.point_wallets
  WHERE user_id = v_caller_id;

  IF v_operation.entity_type = 'asset' THEN
    RETURN jsonb_build_object(
      'status', 'completed',
      'capability_version', '1.1.0',
      'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type,
      'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'asset', (
        SELECT to_jsonb(a) FROM public.assets a
        WHERE a.user_id = v_caller_id AND a.id = v_operation.entity_id
      )
    );
  ELSIF v_operation.entity_type = 'task' THEN
    RETURN jsonb_build_object(
      'status', 'completed',
      'capability_version', '1.1.0',
      'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type,
      'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0),
      'plan', (
        SELECT to_jsonb(p) FROM public.maintenance_plans p
        WHERE p.user_id = v_caller_id AND p.id = v_operation.entity_id
      ),
      'metadata', (
        SELECT to_jsonb(m) FROM public.maintenance_plan_metadata m
        WHERE m.user_id = v_caller_id AND m.plan_id = v_operation.entity_id
      )
    );
  ELSE
    RETURN jsonb_build_object(
      'status', 'completed',
      'capability_version', '1.1.0',
      'operation_id', v_operation.operation_id,
      'entity_type', v_operation.entity_type,
      'entity_id', v_operation.entity_id,
      'charged', v_operation.charged_amount,
      'balance', COALESCE(v_current_balance, 0)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.get_charged_operation_status(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_charged_operation_status(UUID, TEXT) TO authenticated;

COMMIT;

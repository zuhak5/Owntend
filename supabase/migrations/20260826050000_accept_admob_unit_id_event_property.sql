-- AdMob ad-unit identifiers use Google's canonical ca-app-pub form
-- (ca-app-pub-<16 digits>/<10 digits>), which the previous [a-z0-9_] pattern
-- rejected, so every production ad_native_impression/ad_native_click event
-- failed with INVALID_EVENT_PROPERTY before reaching the ledger. Keep the
-- bounded-technical-field contract but validate against the real format.

CREATE OR REPLACE FUNCTION owntend_monetization_private.record_monetization_event_impl(p_event_name text, p_properties jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  caller_id UUID := auth.uid();
  v_key TEXT;
  v_value JSONB;
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
    OR pg_column_size(p_properties) > 4096
  THEN
    RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT';
  END IF;

  -- Event-specific allowlist of technical keys only. Unknown keys are
  -- rejected outright so user content or identifying fields can never be
  -- smuggled into the ledger, and every value is bounded and typed.
  FOR v_key, v_value IN
    SELECT * FROM jsonb_each(p_properties)
  LOOP
    CASE p_event_name
      WHEN 'ad_native_impression', 'ad_native_click' THEN
        IF v_key NOT IN ('screen_name', 'ad_unit_id')
          OR v_key = 'screen_name' AND (
            jsonb_typeof(v_value) <> 'string'
            OR v_value #>> '{}' !~ '^[a-z0-9_]{1,32}$'
          )
          OR v_key = 'ad_unit_id' AND (
            jsonb_typeof(v_value) <> 'string'
            OR v_value #>> '{}' !~ '^ca-app-pub-[0-9]{16}/[0-9]{10}$'
          )
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'ad_interstitial_shown' THEN
        IF v_key NOT IN ('cooldown_remaining_sec', 'session_ad_count')
          OR jsonb_typeof(v_value) <> 'number'
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'cooldown_remaining_sec' AND (
          (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 0 AND 86400
        ) OR v_key = 'session_ad_count' AND (
          (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 0 AND 100
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'ad_rewarded_watched' THEN
        IF v_key NOT IN ('reward_amount', 'entry_point', 'verification') THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'reward_amount' AND (
          jsonb_typeof(v_value) <> 'number'
          OR (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int NOT BETWEEN 1 AND 100
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entry_point' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' !~ '^[a-z0-9_]{1,32}$'
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'verification' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('server_pending')
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'point_shortage_encountered' THEN
        IF v_key NOT IN ('attempted_action')
          OR jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('asset', 'task')
        THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      WHEN 'points_debited' THEN
        IF v_key NOT IN ('entity_type', 'entity_id', 'cost', 'new_balance', 'included_task_count') THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entity_type' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' NOT IN ('asset', 'asset_copy', 'task')
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key = 'entity_id' AND (
          jsonb_typeof(v_value) <> 'string'
          OR v_value #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
        IF v_key IN ('cost', 'new_balance', 'included_task_count') AND (
          jsonb_typeof(v_value) <> 'number'
          OR (v_value #>> '{}')::numeric <> floor((v_value #>> '{}')::numeric)
          OR (v_value #>> '{}')::int < 0
          OR (v_value #>> '{}')::int > CASE
            WHEN v_key = 'cost' THEN 1000
            WHEN v_key = 'new_balance' THEN 100000
            ELSE 50
          END
        ) THEN
          RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT_PROPERTY';
        END IF;
      ELSE
        RAISE EXCEPTION USING errcode = '22023', message = 'INVALID_EVENT';
    END CASE;
  END LOOP;

  INSERT INTO public.monetization_events (user_id, event_name, properties)
  VALUES (caller_id, p_event_name, p_properties);
END;
$function$;

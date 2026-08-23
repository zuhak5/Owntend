-- Fix client_updated_at calculation for profiles in server change feed

CREATE OR REPLACE FUNCTION "owntend_private"."fn_log_server_change_feed"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_row jsonb;
  v_identity jsonb;
  v_user_id uuid;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_user_id := nullif(v_row ->> 'user_id', '')::uuid;
  if v_user_id is null then
    raise exception 'Unsupported change-feed row for table %', tg_table_name;
  end if;
  if not exists (select 1 from auth.users where id = v_user_id) then
    return null;
  end if;
  v_identity := owntend_private.sync_feed_identity(tg_table_name, v_row);
  insert into public.server_change_feed (
    user_id,
    entity_type,
    record_id,
    key_data,
    op_type,
    client_updated_at,
    revision,
    contract_version,
    payload
  ) values (
    v_user_id,
    v_identity ->> 'entity_type',
    v_identity ->> 'record_id',
    v_identity -> 'key_data',
    tg_op,
    coalesce(
      nullif(v_row ->> 'client_modified_at', '')::timestamptz,
      nullif(v_row ->> 'updated_at', '')::timestamptz,
      nullif(v_row ->> 'created_at', '')::timestamptz,
      clock_timestamp()
    ),
    coalesce(nullif(v_row ->> 'revision', '')::bigint, 1),
    1,
    case when tg_op = 'DELETE' then null else v_row end
  );
  return null;
end;
$$;

ALTER FUNCTION "owntend_private"."fn_log_server_change_feed"() OWNER TO "postgres";
REVOKE ALL ON FUNCTION "owntend_private"."fn_log_server_change_feed"() FROM PUBLIC;

UPDATE public.server_change_feed
SET client_updated_at = coalesce(client_updated_at, created_at, clock_timestamp())
WHERE client_updated_at IS NULL;

ALTER TABLE public.server_change_feed
  ALTER COLUMN client_updated_at SET NOT NULL;

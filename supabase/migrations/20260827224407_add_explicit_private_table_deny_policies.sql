-- These operational tables are intentionally inaccessible to Data API roles.
-- Explicit deny policies preserve that fail-closed contract while making the
-- RLS posture machine-auditable (Supabase Advisor lint 0008).

CREATE POLICY maintenance_plan_entitlements_api_roles_deny_all
ON owntend_monetization_private.maintenance_plan_entitlements
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

CREATE POLICY plan_economy_operations_api_roles_deny_all
ON owntend_monetization_private.plan_economy_operations
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

CREATE POLICY maintenance_history_restore_operations_api_roles_deny_all
ON owntend_private.maintenance_history_restore_operations
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

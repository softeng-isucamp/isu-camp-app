-- Performance indexes for ISU-CAMP.
--
-- NOT APPLIED. Review, then run against the project (Supabase SQL editor or
-- `supabase db push`). At current row counts (5-97 rows per table) none of this
-- changes latency; it matters before UserHistory grows.
--
-- Every statement is CONCURRENTLY so it does not lock the table. That means
-- each must run OUTSIDE a transaction block - run them one at a time, not as
-- one batched script.

-- 1. The hottest user-facing query. GET /history filters User_id and orders by
--    (created_at DESC, id DESC); no index covers that today.
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_user_history_user_created
    ON public."UserHistory" ("User_id", created_at DESC, id DESC);

-- Superseded by the composite above: the linter reports all three as never
-- used, and they only slow inserts down.
DROP INDEX CONCURRENTLY IF EXISTS public.ix_user_history_created_at;
DROP INDEX CONCURRENTLY IF EXISTS public.ix_user_history_building_created_at;
DROP INDEX CONCURRENTLY IF EXISTS public.ix_user_history_location_created_at;

-- 2. Unindexed foreign keys. These make the FK checks and the joins in
--    /campus/buildings and /auth/login seq scans as the tables grow.
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_location_building
    ON public.location (building_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_location_floor
    ON public.location (floor_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_location_type
    ON public.location (type_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_route_node_building
    ON public.route_node (building_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_route_node_location
    ON public.route_node (location_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_path_point_building
    ON public.path_point (building_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS ix_user_info
    ON public."user" (info_id);

-- 3. path_point has two identical unique indexes; keep one.
DROP INDEX CONCURRENTLY IF EXISTS public.unique_pathway_sequence;

-- 4. Login lookup keys: `user.username` and `userInfo.email` currently have NO
--    index and NO unique constraint - only the primary keys exist. Two
--    consequences:
--      * every login by username or email is a sequential scan;
--      * uniqueness is enforced only in application code
--        (app/routes/auth.py request_otp), so two concurrent signups with the
--        same email can both pass the check and both insert.
--    Verified 2026-09-21: no duplicate or null usernames/emails exist, so these
--    can be created as UNIQUE today. Confirm that again before running.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ix_user_username
    ON public."user" (username);
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS ix_userinfo_email
    ON public."userInfo" (email);

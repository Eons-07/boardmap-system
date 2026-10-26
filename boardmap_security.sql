-- BoardMap | IT 108 Laboratory Activity 7 | security setup for schema system_core
-- Run as the schema owner / superuser on the TEST database only. Run schema.sql first.
-- NEVER commit a real password: set boardmap_api's password separately in pgAdmin (ALTER ROLE ... PASSWORD) and keep it in .env.

-- ============================================================
-- 1. ROLES  (3 application roles -> 3 NOLOGIN group roles; 1 LOGIN role for the FastAPI backend)
-- ============================================================
DO $$ BEGIN  -- roles are cluster-wide, so this block keeps the script safe to re-run
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bm_student') THEN CREATE ROLE bm_student NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bm_owner') THEN CREATE ROLE bm_owner NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'bm_admin') THEN CREATE ROLE bm_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'boardmap_api') THEN CREATE ROLE boardmap_api LOGIN NOINHERIT; END IF;  -- NOINHERIT: holds no group privileges until the backend runs SET LOCAL ROLE
END $$;
GRANT bm_student, bm_owner, bm_admin TO boardmap_api;

-- ============================================================
-- 2. SCHEMA PRIVILEGES
-- ============================================================
REVOKE CREATE ON SCHEMA public FROM PUBLIC;  -- closes the PostgreSQL <= 14 default where everyone can create objects in public
GRANT USAGE ON SCHEMA system_core TO bm_student, bm_owner, bm_admin, boardmap_api;  -- USAGE only, nobody gets CREATE

-- ============================================================
-- 3. IDENTITY HELPERS  (the backend supplies the user id with set_config('app.user_id', ..., true))
-- ============================================================
CREATE OR REPLACE FUNCTION system_core.app_user_id() RETURNS int LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('app.user_id', true), '')::int $$;

CREATE OR REPLACE FUNCTION system_core.app_owner_id() RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = system_core, pg_temp
AS $$ SELECT owner_id FROM boarding_house_owners WHERE user_id = system_core.app_user_id() $$;

REVOKE EXECUTE ON FUNCTION system_core.app_user_id(), system_core.app_owner_id() FROM PUBLIC;  -- functions are EXECUTE-for-everyone by default
GRANT EXECUTE ON FUNCTION system_core.app_user_id(), system_core.app_owner_id() TO bm_student, bm_owner, bm_admin;

-- ============================================================
-- 4. TABLE PRIVILEGES  (audited tables: users, boarding_houses, rooms, reviews, reports)
-- ============================================================
-- users: the password column is never readable by bm_* roles, so the backend must list columns (no SELECT *)
GRANT SELECT (user_id, full_name, email, contact_number, role, date_registered) ON system_core.users TO bm_student, bm_owner, bm_admin;
GRANT UPDATE (full_name, contact_number, password) ON system_core.users TO bm_student, bm_owner;
GRANT UPDATE (full_name, contact_number, role), DELETE ON system_core.users TO bm_admin;
-- login / registration run before a role is known, so boardmap_api gets a narrow direct grant
GRANT SELECT (user_id, email, password, role), INSERT (full_name, email, password, contact_number, role) ON system_core.users TO boardmap_api;
GRANT USAGE ON SEQUENCE system_core.users_user_id_seq TO boardmap_api;
-- owner registration also creates the owners row (verification_status stays 'pending' by default)
GRANT INSERT (user_id, name, email, contact_number) ON system_core.boarding_house_owners TO boardmap_api;
GRANT USAGE ON SEQUENCE system_core.boarding_house_owners_owner_id_seq TO boardmap_api;

-- boarding_houses: owners cannot touch status (admin approval workflow); nobody except admin can DELETE
GRANT SELECT ON system_core.boarding_houses TO bm_student, bm_owner, bm_admin;
GRANT INSERT (owner_id, location_id, house_name, description, capacity, contact_number) ON system_core.boarding_houses TO bm_owner;
GRANT UPDATE (location_id, house_name, description, capacity, contact_number) ON system_core.boarding_houses TO bm_owner;
GRANT UPDATE (status), DELETE ON system_core.boarding_houses TO bm_admin;
GRANT USAGE ON SEQUENCE system_core.boarding_houses_boarding_house_id_seq TO bm_owner;

-- rooms
GRANT SELECT ON system_core.rooms TO bm_student, bm_owner, bm_admin;
GRANT INSERT, UPDATE, DELETE ON system_core.rooms TO bm_owner;
GRANT UPDATE (status), DELETE ON system_core.rooms TO bm_admin;
GRANT USAGE ON SEQUENCE system_core.rooms_room_id_seq TO bm_owner;

-- reviews: students manage their own; admin moderates by deleting
GRANT SELECT ON system_core.reviews TO bm_student, bm_owner, bm_admin;
GRANT INSERT (user_id, boarding_house_id, rating, comment) ON system_core.reviews TO bm_student;
GRANT UPDATE (rating, comment), DELETE ON system_core.reviews TO bm_student;
GRANT DELETE ON system_core.reviews TO bm_admin;
GRANT USAGE ON SEQUENCE system_core.reviews_review_id_seq TO bm_student;

-- reports: students file them, admin changes status; nobody can DELETE (audit trail); owners have no access
GRANT SELECT ON system_core.reports TO bm_student, bm_admin;
GRANT INSERT (user_id, boarding_house_id, report_type, description) ON system_core.reports TO bm_student;
GRANT UPDATE (status) ON system_core.reports TO bm_admin;
GRANT USAGE ON SEQUENCE system_core.reports_report_id_seq TO bm_student;

-- read-only lookup data outside the 5 audited tables, so listing pages can render
GRANT SELECT ON system_core.locations, system_core.amenities, system_core.boarding_house_amenities, system_core.boarding_house_images TO bm_student, bm_owner, bm_admin;

-- reviewer names without opening the users table (view runs with the owner's rights, so it filters to approved houses itself)
CREATE OR REPLACE VIEW system_core.v_sec_public_reviews AS
SELECT r.review_id, r.boarding_house_id, u.full_name AS reviewer_name, r.rating, r.comment, r.review_date
FROM system_core.reviews r JOIN system_core.users u ON u.user_id = r.user_id JOIN system_core.boarding_houses b ON b.boarding_house_id = r.boarding_house_id
WHERE b.status = 'approved';
GRANT SELECT ON system_core.v_sec_public_reviews TO bm_student, bm_owner, bm_admin;

-- ============================================================
-- 5. ROW-LEVEL SECURITY  (tables must stay owned by the migration role, never by boardmap_api or bm_*, or RLS is bypassed)
-- ============================================================
ALTER TABLE system_core.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY users_self_select ON system_core.users FOR SELECT TO bm_student, bm_owner USING (user_id = system_core.app_user_id());
CREATE POLICY users_self_update ON system_core.users FOR UPDATE TO bm_student, bm_owner USING (user_id = system_core.app_user_id()) WITH CHECK (user_id = system_core.app_user_id());
CREATE POLICY users_admin_all ON system_core.users FOR ALL TO bm_admin USING (true) WITH CHECK (true);
CREATE POLICY users_api_select ON system_core.users FOR SELECT TO boardmap_api USING (true);
CREATE POLICY users_api_insert ON system_core.users FOR INSERT TO boardmap_api WITH CHECK (role IN ('student', 'owner'));  -- nobody can self-register as admin

ALTER TABLE system_core.boarding_houses ENABLE ROW LEVEL SECURITY;
CREATE POLICY bh_student_select ON system_core.boarding_houses FOR SELECT TO bm_student USING (status = 'approved');
CREATE POLICY bh_owner_select ON system_core.boarding_houses FOR SELECT TO bm_owner USING (status = 'approved' OR owner_id = system_core.app_owner_id());
CREATE POLICY bh_owner_insert ON system_core.boarding_houses FOR INSERT TO bm_owner WITH CHECK (owner_id = system_core.app_owner_id());
CREATE POLICY bh_owner_update ON system_core.boarding_houses FOR UPDATE TO bm_owner USING (owner_id = system_core.app_owner_id()) WITH CHECK (owner_id = system_core.app_owner_id());
CREATE POLICY bh_admin_all ON system_core.boarding_houses FOR ALL TO bm_admin USING (true) WITH CHECK (true);

ALTER TABLE system_core.rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY rooms_student_select ON system_core.rooms FOR SELECT TO bm_student USING (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id AND b.status = 'approved'));
CREATE POLICY rooms_owner_select ON system_core.rooms FOR SELECT TO bm_owner USING (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id));  -- boarding_houses policy already limits b to approved-or-own
CREATE POLICY rooms_owner_insert ON system_core.rooms FOR INSERT TO bm_owner WITH CHECK (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id AND b.owner_id = system_core.app_owner_id()));
CREATE POLICY rooms_owner_update ON system_core.rooms FOR UPDATE TO bm_owner USING (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id AND b.owner_id = system_core.app_owner_id())) WITH CHECK (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id AND b.owner_id = system_core.app_owner_id()));
CREATE POLICY rooms_owner_delete ON system_core.rooms FOR DELETE TO bm_owner USING (EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = rooms.boarding_house_id AND b.owner_id = system_core.app_owner_id()));
CREATE POLICY rooms_admin_all ON system_core.rooms FOR ALL TO bm_admin USING (true) WITH CHECK (true);

ALTER TABLE system_core.reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY reviews_read ON system_core.reviews FOR SELECT TO bm_student, bm_owner, bm_admin USING (true);
CREATE POLICY reviews_student_insert ON system_core.reviews FOR INSERT TO bm_student WITH CHECK (user_id = system_core.app_user_id() AND EXISTS (SELECT 1 FROM system_core.boarding_houses b WHERE b.boarding_house_id = reviews.boarding_house_id));  -- b is filtered to approved houses by bh_student_select
CREATE POLICY reviews_student_update ON system_core.reviews FOR UPDATE TO bm_student USING (user_id = system_core.app_user_id()) WITH CHECK (user_id = system_core.app_user_id());
CREATE POLICY reviews_student_delete ON system_core.reviews FOR DELETE TO bm_student USING (user_id = system_core.app_user_id());
CREATE POLICY reviews_admin_delete ON system_core.reviews FOR DELETE TO bm_admin USING (true);

ALTER TABLE system_core.reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY reports_student_select ON system_core.reports FOR SELECT TO bm_student USING (user_id = system_core.app_user_id());
CREATE POLICY reports_student_insert ON system_core.reports FOR INSERT TO bm_student WITH CHECK (user_id = system_core.app_user_id());
CREATE POLICY reports_admin_select ON system_core.reports FOR SELECT TO bm_admin USING (true);
CREATE POLICY reports_admin_update ON system_core.reports FOR UPDATE TO bm_admin USING (true) WITH CHECK (true);

-- Not yet covered (no privileges granted, so access is denied by default): user_preferences,
-- user_preference_amenities, favorites, recommendations, ml_prediction_results. Extend the matrix before the backend uses them.

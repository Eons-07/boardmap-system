-- BoardMap | Activity 7 | allowed-vs-denied tests. Run as a superuser on the TEST database AFTER boardmap_security.sql.
-- Everything runs in one transaction and ends with ROLLBACK, so no test data stays. Read the PASS/FAIL lines in pgAdmin's Messages tab.
BEGIN;

INSERT INTO system_core.users (user_id, full_name, email, password, role) VALUES
(90001, 'Test Student', 't_student@test.local', 'x', 'student'), (90002, 'Test Owner One', 't_owner1@test.local', 'x', 'owner'),
(90003, 'Test Owner Two', 't_owner2@test.local', 'x', 'owner'), (90004, 'Test Admin', 't_admin@test.local', 'x', 'admin');
INSERT INTO system_core.boarding_house_owners (owner_id, user_id, name, email) VALUES (90002, 90002, 'Test Owner One', 'o1@test.local'), (90003, 90003, 'Test Owner Two', 'o2@test.local');
INSERT INTO system_core.locations (location_id, barangay_name, city) VALUES (90001, 'Test Brgy', 'Test City');
INSERT INTO system_core.boarding_houses (boarding_house_id, owner_id, location_id, house_name, status) VALUES
(90001, 90002, 90001, 'T Approved House', 'approved'), (90002, 90002, 90001, 'T Pending House', 'pending'), (90003, 90003, 90001, 'T Other Owner House', 'approved');

-- helper: act as a role + user id, run one statement, compare with the expected outcome
CREATE FUNCTION pg_temp.t(tid text, who text, uid int, stmt text, expect text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n bigint; r text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', who);
  PERFORM set_config('app.user_id', coalesce(uid::text, ''), true);
  BEGIN
    EXECUTE stmt; GET DIAGNOSTICS n = ROW_COUNT; r := 'OK rows=' || n;
  EXCEPTION WHEN insufficient_privilege THEN r := 'DENIED';
            WHEN OTHERS THEN r := 'ERROR ' || sqlstate;
  END;
  RESET ROLE;
  RAISE NOTICE '% | % | % | expected: % | got: % | %', CASE WHEN r = expect THEN 'PASS' ELSE 'FAIL' END, tid, who, expect, r, left(regexp_replace(stmt, '\s+', ' ', 'g'), 90);
END $$;

-- STUDENT (user 90001)
SELECT pg_temp.t('T01', 'bm_student', 90001, $q$SELECT 1 FROM system_core.boarding_houses WHERE boarding_house_id = 90001$q$, 'OK rows=1');
SELECT pg_temp.t('T02', 'bm_student', 90001, $q$SELECT 1 FROM system_core.boarding_houses WHERE boarding_house_id = 90002$q$, 'OK rows=0');
SELECT pg_temp.t('T03', 'bm_student', 90001, $q$UPDATE system_core.boarding_houses SET house_name = 'hacked' WHERE boarding_house_id = 90001$q$, 'DENIED');
SELECT pg_temp.t('T04', 'bm_student', 90001, $q$SELECT password FROM system_core.users WHERE user_id = 90001$q$, 'DENIED');
SELECT pg_temp.t('T05', 'bm_student', 90001, $q$SELECT email FROM system_core.users WHERE user_id = 90001$q$, 'OK rows=1');
SELECT pg_temp.t('T06', 'bm_student', 90001, $q$SELECT email FROM system_core.users WHERE user_id = 90004$q$, 'OK rows=0');
SELECT pg_temp.t('T07', 'bm_student', 90001, $q$DELETE FROM system_core.users WHERE user_id = 90004$q$, 'DENIED');
SELECT pg_temp.t('T08', 'bm_student', 90001, $q$INSERT INTO system_core.reports (user_id, boarding_house_id, report_type, description) VALUES (90001, 90001, 'Incorrect price', 'sec-test report')$q$, 'OK rows=1');
SELECT pg_temp.t('T09', 'bm_student', 90001, $q$INSERT INTO system_core.reports (user_id, boarding_house_id, report_type, description) VALUES (90004, 90001, 'Incorrect price', 'forged')$q$, 'DENIED');
SELECT pg_temp.t('T10', 'bm_student', 90001, $q$UPDATE system_core.reports SET status = 'resolved' WHERE description = 'sec-test report'$q$, 'DENIED');
SELECT pg_temp.t('T11', 'bm_student', 90001, $q$INSERT INTO system_core.reviews (user_id, boarding_house_id, rating, comment) VALUES (90001, 90001, 5, 'sec-test review')$q$, 'OK rows=1');
SELECT pg_temp.t('T12', 'bm_student', 90001, $q$INSERT INTO system_core.reviews (user_id, boarding_house_id, rating, comment) VALUES (90001, 90002, 5, 'review of unapproved house')$q$, 'DENIED');

-- OWNER ONE (user 90002, owner 90002); owner two is 90003
SELECT pg_temp.t('T13', 'bm_owner', 90002, $q$UPDATE system_core.boarding_houses SET description = 'edited' WHERE boarding_house_id = 90001$q$, 'OK rows=1');
SELECT pg_temp.t('T14', 'bm_owner', 90002, $q$UPDATE system_core.boarding_houses SET description = 'edited' WHERE boarding_house_id = 90003$q$, 'OK rows=0');
SELECT pg_temp.t('T15', 'bm_owner', 90002, $q$UPDATE system_core.boarding_houses SET status = 'approved' WHERE boarding_house_id = 90002$q$, 'DENIED');
SELECT pg_temp.t('T16', 'bm_owner', 90002, $q$INSERT INTO system_core.boarding_houses (owner_id, location_id, house_name) VALUES (90003, 90001, 'listing for another owner')$q$, 'DENIED');
SELECT pg_temp.t('T17', 'bm_owner', 90002, $q$INSERT INTO system_core.boarding_houses (owner_id, location_id, house_name) VALUES (90002, 90001, 'my new listing')$q$, 'OK rows=1');
SELECT pg_temp.t('T18a', 'bm_owner', 90002, $q$INSERT INTO system_core.rooms (boarding_house_id, room_type, price, capacity, available_slots) VALUES (90001, 'single', 1500, 1, 1)$q$, 'OK rows=1');
SELECT pg_temp.t('T18b', 'bm_owner', 90002, $q$INSERT INTO system_core.rooms (boarding_house_id, room_type, price, capacity, available_slots) VALUES (90003, 'single', 1500, 1, 1)$q$, 'DENIED');
SELECT pg_temp.t('T19', 'bm_owner', 90002, $q$SELECT 1 FROM system_core.reports$q$, 'DENIED');
SELECT pg_temp.t('T20', 'bm_owner', 90002, $q$INSERT INTO system_core.reviews (user_id, boarding_house_id, rating) VALUES (90002, 90003, 5)$q$, 'DENIED');

-- ADMIN (user 90004)
SELECT pg_temp.t('T21', 'bm_admin', 90004, $q$UPDATE system_core.boarding_houses SET status = 'approved' WHERE boarding_house_id = 90002$q$, 'OK rows=1');
SELECT pg_temp.t('T22', 'bm_admin', 90004, $q$SELECT password FROM system_core.users$q$, 'DENIED');
SELECT pg_temp.t('T23', 'bm_admin', 90004, $q$UPDATE system_core.reports SET status = 'reviewing' WHERE description = 'sec-test report'$q$, 'OK rows=1');
SELECT pg_temp.t('T24', 'bm_admin', 90004, $q$DELETE FROM system_core.reports$q$, 'DENIED');

-- BACKEND LOGIN ROLE (no group role active)
SELECT pg_temp.t('T25', 'boardmap_api', NULL, $q$SELECT user_id, email, password, role FROM system_core.users WHERE email = 't_student@test.local'$q$, 'OK rows=1');
SELECT pg_temp.t('T26', 'boardmap_api', NULL, $q$INSERT INTO system_core.users (full_name, email, password, role) VALUES ('Evil', 'evil@test.local', 'x', 'admin')$q$, 'DENIED');
SELECT pg_temp.t('T27', 'boardmap_api', NULL, $q$INSERT INTO system_core.users (full_name, email, password, role) VALUES ('Okay', 'okay@test.local', 'x', 'student')$q$, 'OK rows=1');
SELECT pg_temp.t('T28', 'boardmap_api', NULL, $q$SELECT 1 FROM system_core.boarding_houses$q$, 'DENIED');

-- REVOKE DEMONSTRATION (rolled back with everything else): the same statement is allowed, then rejected after the REVOKE
SELECT pg_temp.t('T29', 'bm_owner', 90002, $q$DELETE FROM system_core.rooms WHERE boarding_house_id = 90001$q$, 'OK rows=1');
REVOKE DELETE ON system_core.rooms FROM bm_owner;
SELECT pg_temp.t('T30', 'bm_owner', 90002, $q$DELETE FROM system_core.rooms WHERE boarding_house_id = 90001$q$, 'DENIED');

-- PRIVILEGE CHECKS
SELECT has_function_privilege('boardmap_api', 'system_core.app_owner_id()', 'EXECUTE') AS api_can_run_owner_fn, has_function_privilege('bm_owner', 'system_core.app_owner_id()', 'EXECUTE') AS owner_role_can_run_owner_fn, has_schema_privilege('bm_student', 'public', 'CREATE') AS student_can_create_in_public;

ROLLBACK;

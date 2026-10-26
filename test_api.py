# Run: python test_api.py   (needs DATABASE_URL, JWT_SECRET in the environment and SUPER_URL = a superuser URL for seeding the TEST db)
import os, bcrypt
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from app.main import app
cl = TestClient(app); su = create_engine(os.environ["SUPER_URL"]); fails = 0
def chk(name, ok):
    global fails; fails += (not ok); print(("PASS" if ok else "FAIL"), "|", name)
h = bcrypt.hashpw(b"AdminPass123", bcrypt.gensalt()).decode()
with su.begin() as c:
    c.execute(text("INSERT INTO system_core.users (user_id, full_name, email, password, role) VALUES (95001,'Sec Admin','sec_admin@test.local',:h,'admin')"), {"h": h})
    c.execute(text("INSERT INTO system_core.locations (location_id, barangay_name, city) VALUES (95001,'Sec Brgy','Sec City')"))
r = cl.post("/api/auth/register", json={"full_name": "Sec Owner", "email": "sec_owner@test.local", "password": "OwnerPass123", "role": "owner"}); chk("register owner -> 201", r.status_code == 201)
oid = r.json()["user_id"]
with su.begin() as c:
    own = c.execute(text("SELECT owner_id FROM system_core.boarding_house_owners WHERE user_id = :u"), {"u": oid}).scalar_one()
    c.execute(text("INSERT INTO system_core.boarding_houses (boarding_house_id, owner_id, location_id, house_name, status) VALUES (95001,:o,95001,'Sec Approved House','approved'),(95002,:o,95001,'Sec Pending House','pending')"), {"o": own})
    c.execute(text("INSERT INTO system_core.rooms (boarding_house_id, room_type, price, capacity, available_slots) VALUES (95001,'single',1500,1,1)"))
chk("register student -> 201", cl.post("/api/auth/register", json={"full_name": "Sec Student", "email": "sec_student@test.local", "password": "StudentPass123"}).status_code == 201)
chk("duplicate email -> 409", cl.post("/api/auth/register", json={"full_name": "x", "email": "sec_student@test.local", "password": "StudentPass123"}).status_code == 409)
chk("self-register as admin -> 422", cl.post("/api/auth/register", json={"full_name": "x", "email": "evil@test.local", "password": "EvilPass1234", "role": "admin"}).status_code == 422)
with su.begin() as c: stored = c.execute(text("SELECT password FROM system_core.users WHERE email='sec_student@test.local'")).scalar_one()
chk("stored password is a bcrypt hash, not plaintext", stored.startswith("$2") and "StudentPass123" not in stored)
chk("wrong password -> 401", cl.post("/api/auth/login", json={"email": "sec_student@test.local", "password": "nope"}).status_code == 401)
chk("SQL-injection login payload -> 401", cl.post("/api/auth/login", json={"email": "' OR '1'='1' --", "password": "x"}).status_code == 401)
tok = lambda e, p: {"Authorization": "Bearer " + cl.post("/api/auth/login", json={"email": e, "password": p}).json()["access_token"]}
S = tok("sec_student@test.local", "StudentPass123"); O = tok("sec_owner@test.local", "OwnerPass123"); A = tok("sec_admin@test.local", "AdminPass123")
chk("no token -> 401/403", cl.get("/api/boarding-houses").status_code in (401, 403))
chk("tampered token -> 401", cl.get("/api/boarding-houses", headers={"Authorization": S["Authorization"][:-3] + "abc"}).status_code == 401)
names = lambda hd, **p: [x["house_name"] for x in cl.get("/api/boarding-houses", headers=hd, params=p).json()]
chk("student sees approved house only", "Sec Approved House" in names(S) and "Sec Pending House" not in names(S))
chk("owner sees own pending house", "Sec Pending House" in names(O))
chk("admin sees pending house", "Sec Pending House" in names(A))
chk("search term filters results", names(S, q="Approved") == ["Sec Approved House"])
chk("max_price filter works", names(S, max_price=1000) == [] and names(S, max_price=2000) == ["Sec Approved House"])
chk("SQL-injection search payload returns nothing, no error", names(S, q="x' OR '1'='1") == [])
with su.begin() as c:
    for t in ("rooms", "boarding_houses", "boarding_house_owners", "locations", "users"): c.execute(text(f"DELETE FROM system_core.{t} WHERE " + {"rooms": "boarding_house_id IN (95001,95002)", "boarding_houses": "boarding_house_id IN (95001,95002)", "boarding_house_owners": "email LIKE 'sec_%@test.local'", "locations": "location_id = 95001", "users": "email LIKE 'sec_%@test.local'"}[t]))
print("FAILED:", fails); raise SystemExit(fails)

from datetime import datetime, timedelta, timezone
from typing import Literal, Optional
import bcrypt, jwt
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from app import config
from app.db import auth_conn, role_conn
app = FastAPI(title="BoardMap API")
bearer = HTTPBearer()
class RegisterIn(BaseModel):
    full_name: str = Field(min_length=1, max_length=150)
    email: str = Field(min_length=3, max_length=150)
    password: str = Field(min_length=8, max_length=72)
    contact_number: Optional[str] = Field(default=None, max_length=20)
    role: Literal["student", "owner"] = "student"  # 'admin' is rejected here AND by the users_api_insert RLS policy
class LoginIn(BaseModel):
    email: str
    password: str
def current_user(c: HTTPAuthorizationCredentials = Depends(bearer)):
    try: p = jwt.decode(c.credentials, config.JWT_SECRET, algorithms=[config.JWT_ALGORITHM])
    except jwt.PyJWTError: raise HTTPException(401, "Invalid or expired token")
    return int(p["sub"]), p["role"]
@app.post("/api/auth/register", status_code=201)
def register(b: RegisterIn):
    hashed = bcrypt.hashpw(b.password.encode(), bcrypt.gensalt()).decode()  # only the hash ever reaches users.password
    try:
        with auth_conn() as c:
            uid = c.execute(text("INSERT INTO system_core.users (full_name, email, password, contact_number, role) VALUES (:n, :e, :p, :c, :r) RETURNING user_id"), {"n": b.full_name, "e": b.email, "p": hashed, "c": b.contact_number, "r": b.role}).scalar_one()
            if b.role == "owner": c.execute(text("INSERT INTO system_core.boarding_house_owners (user_id, name, email, contact_number) VALUES (:u, :n, :e, :c)"), {"u": uid, "n": b.full_name, "e": b.email, "c": b.contact_number})
    except IntegrityError: raise HTTPException(409, "Email already registered")
    return {"user_id": uid, "role": b.role}
@app.post("/api/auth/login")
def login(b: LoginIn):
    with auth_conn() as c:
        row = c.execute(text("SELECT user_id, password, role FROM system_core.users WHERE email = :email"), {"email": b.email}).first()  # REVIEWED QUERY (Part F)
    if row is None or not bcrypt.checkpw(b.password.encode(), row.password.encode()): raise HTTPException(401, "Invalid email or password")
    exp = datetime.now(timezone.utc) + timedelta(minutes=config.JWT_MINUTES)
    return {"access_token": jwt.encode({"sub": str(row.user_id), "role": row.role, "exp": exp}, config.JWT_SECRET, algorithm=config.JWT_ALGORITHM), "token_type": "bearer"}
@app.get("/api/boarding-houses")
def search_boarding_houses(q: str = "", max_price: Optional[float] = None, me=Depends(current_user)):
    uid, role = me
    with role_conn(role, uid) as c:  # RLS decides which rows this role may see: students get approved listings only
        rows = c.execute(text("""SELECT b.boarding_house_id, b.house_name, l.barangay_name, MIN(r.price) AS min_price
            FROM system_core.boarding_houses b JOIN system_core.locations l ON l.location_id = b.location_id
            LEFT JOIN system_core.rooms r ON r.boarding_house_id = b.boarding_house_id
            WHERE b.house_name ILIKE :q GROUP BY b.boarding_house_id, b.house_name, l.barangay_name
            HAVING CAST(:mp AS numeric) IS NULL OR MIN(r.price) <= CAST(:mp AS numeric) ORDER BY b.house_name"""), {"q": f"%{q}%", "mp": max_price}).mappings().all()  # REVIEWED QUERY (Part F)
    return [{**r, "min_price": float(r["min_price"]) if r["min_price"] is not None else None} for r in rows]

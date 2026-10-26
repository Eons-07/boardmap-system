from contextlib import contextmanager
from sqlalchemy import create_engine, text
from app.config import DATABASE_URL
engine = create_engine(DATABASE_URL, pool_pre_ping=True)  # logs in as boardmap_api, a NOINHERIT role with narrow grants
# Allowlist of complete statements: SET ROLE cannot take bind parameters, so the role name is never built from input.
ROLE_SQL = {"student": text("SET LOCAL ROLE bm_student"), "owner": text("SET LOCAL ROLE bm_owner"), "admin": text("SET LOCAL ROLE bm_admin")}
@contextmanager
def auth_conn():  # login/register: no app role exists yet, so boardmap_api acts as itself
    with engine.begin() as conn: yield conn
@contextmanager
def role_conn(app_role: str, user_id: int):  # every other request: drop to the caller's DB role for this transaction only
    with engine.begin() as conn:
        conn.execute(ROLE_SQL[app_role])  # KeyError for any role outside the allowlist
        conn.execute(text("SELECT set_config('app.user_id', :uid, true)"), {"uid": str(user_id)})  # read by the RLS policies
        yield conn  # SET LOCAL and set_config(..., true) both reset at commit/rollback, so pooled connections never leak identity

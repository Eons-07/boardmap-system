import os
from dotenv import load_dotenv
load_dotenv()  # reads backend/.env on a developer machine; that file is listed in .gitignore
DATABASE_URL = os.environ["DATABASE_URL"]  # KeyError at startup if missing: no hard-coded fallback exists
JWT_SECRET = os.environ["JWT_SECRET"]
JWT_ALGORITHM = "HS256"
JWT_MINUTES = int(os.getenv("JWT_MINUTES", "60"))

# FastAPI entry point: registers middleware and API routers.
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database.supabase import supabase
from app.routes.auth import router as auth_router
from app.routes.login import router as login_router
from app.routes.campus import router as campus_router
from app.routes.history import router as history_router
from app.routes.profile import router as profile_router
from app.routes.captcha import router as captcha_router


app = FastAPI(title="ISU-CAMP Backend")


# ==========================================
# CORS
# ==========================================

# This block allows cross-origin requests and exposes login retry headers to browser clients.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=[
        "Retry-After",
        "X-Login-Attempts",
        "X-Login-Attempts-Remaining",
    ],
)


# ==========================================
# ROUTERS
# ==========================================

# This block registers each router's endpoints in the same FastAPI application.
app.include_router(auth_router)
app.include_router(login_router)
app.include_router(campus_router)
app.include_router(history_router)
app.include_router(profile_router)
app.include_router(captcha_router)


# ==========================================
# ROOT
# ==========================================

# This block returns a simple response to check whether the backend is running.
@app.get("/")
def root():
    return {"message": "ISU-CAMP Backend is running"}


# ==========================================
# TEST SUPABASE
# ==========================================

# This block attempts to read up to five building records to check the database connection.
@app.get("/test-supabase")
def test_supabase():
    try:
        response = (
            supabase
            .table("building")
            .select("*")
            .limit(5)
            .execute()
        )

        return {
            "success": True,
            "data": response.data
        }

    except Exception as e:
        return {
            "success": False,
            "error": str(e)
        }

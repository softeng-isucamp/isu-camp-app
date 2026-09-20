from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database.supabase import supabase
from app.routes.auth import router as auth_router
from app.routes.login import router as login_router
from app.routes.campus import router as campus_router
from app.routes.history import router as history_router


app = FastAPI(title="ISU-CAMP Backend")


# ==========================================
# CORS
# ==========================================

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

app.include_router(auth_router)
app.include_router(login_router)
app.include_router(campus_router)
app.include_router(history_router)


# ==========================================
# ROOT
# ==========================================

@app.get("/")
def root():
    return {"message": "ISU-CAMP Backend is running"}


# ==========================================
# TEST SUPABASE
# ==========================================

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

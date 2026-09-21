from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from starlette.concurrency import run_in_threadpool

from app.routes.auth import router as auth_router
from app.routes.login import router as login_router
from app.routes.campus import router as campus_router
from app.routes.history import router as history_router
from app.utils import campus_cache


# ==========================================
# LIFESPAN
# ==========================================

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load the campus snapshot before serving, so the first user does not pay
    # for the cold cache. warm() swallows its own errors: a Supabase outage
    # must not stop the server from starting.
    await run_in_threadpool(campus_cache.warm)
    yield


app = FastAPI(title="ISU-CAMP Backend", lifespan=lifespan)


# ==========================================
# MIDDLEWARE
# ==========================================

# Route and building payloads are long arrays of repeated decimal strings going
# over plain HTTP to a phone; gzip takes 70-85% off. Nothing else compresses
# them - there is no reverse proxy in front of this.
app.add_middleware(GZipMiddleware, minimum_size=1000)

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

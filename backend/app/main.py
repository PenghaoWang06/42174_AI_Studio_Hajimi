from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.cards import router as cards_router
from app.api.contacts import router as contacts_router
from app.api.health import router as health_router
from app.core.config import settings
from app.db.database import init_db
from app.services.image_storage import ensure_storage_dirs


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    init_db()
    ensure_storage_dirs()
    yield


app = FastAPI(title=settings.app_name, lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(settings.cors_origins),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health_router)
app.include_router(cards_router)
app.include_router(contacts_router)
ensure_storage_dirs()
app.mount("/storage", StaticFiles(directory=settings.storage_dir), name="storage")

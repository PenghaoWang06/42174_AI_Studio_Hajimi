from fastapi import APIRouter

from app.db.database import init_db


router = APIRouter(tags=["health"])


@router.get("/health")
def health_check() -> dict[str, str]:
    init_db()
    return {"status": "ok", "database": "ready"}

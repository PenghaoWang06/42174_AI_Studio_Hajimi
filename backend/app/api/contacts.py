from fastapi import APIRouter, HTTPException, Query, Response, status

from app.db import crud
from app.db.database import get_connection
from app.db.schemas import Contact, ContactCreate, ContactList, ContactUpdate
from app.services.storage_cleanup import delete_storage_files


router = APIRouter(prefix="/contacts", tags=["contacts"])


@router.post("", response_model=Contact, status_code=status.HTTP_201_CREATED)
def create_contact(payload: ContactCreate) -> dict:
    with get_connection() as connection:
        return crud.create_contact(connection, payload)


@router.get("", response_model=ContactList)
def list_contacts(
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> dict:
    with get_connection() as connection:
        items, total = crud.list_contacts(connection, limit=limit, offset=offset)
        return {"items": items, "total": total}


@router.get("/search", response_model=ContactList)
def search_contacts(
    q: str = Query(min_length=1),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
) -> dict:
    with get_connection() as connection:
        items, total = crud.search_contacts(
            connection,
            query=q,
            limit=limit,
            offset=offset,
        )
        return {"items": items, "total": total}


@router.get("/{contact_id}", response_model=Contact)
def get_contact(contact_id: int) -> dict:
    with get_connection() as connection:
        contact = crud.get_contact(connection, contact_id)
        if contact is None:
            raise HTTPException(status_code=404, detail="Contact not found")
        return contact


@router.put("/{contact_id}", response_model=Contact)
def update_contact(contact_id: int, payload: ContactUpdate) -> dict:
    with get_connection() as connection:
        contact = crud.update_contact(connection, contact_id, payload)
        if contact is None:
            raise HTTPException(status_code=404, detail="Contact not found")
        return contact


@router.delete("/{contact_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_contact(contact_id: int) -> Response:
    paths_to_delete: list[str] = []
    with get_connection() as connection:
        contact = crud.get_contact(connection, contact_id)
        if contact is None:
            raise HTTPException(status_code=404, detail="Contact not found")
        deleted = crud.delete_contact(connection, contact_id)
        if not deleted:
            raise HTTPException(status_code=404, detail="Contact not found")
        paths_to_delete = crud.find_unreferenced_asset_paths(
            connection,
            [contact.get("image_path"), contact.get("crop_path")],
        )
    delete_storage_files(paths_to_delete)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

from pydantic import BaseModel, Field


class ContactBase(BaseModel):
    name: str | None = Field(default=None, max_length=255)
    company: str | None = Field(default=None, max_length=255)
    email: str | None = Field(default=None, max_length=255)
    phone: str | None = Field(default=None, max_length=64)
    raw_text: str | None = None
    image_path: str | None = Field(default=None, max_length=1024)
    crop_path: str | None = Field(default=None, max_length=1024)


class ContactCreate(ContactBase):
    pass


class ContactUpdate(ContactBase):
    pass


class Contact(ContactBase):
    id: int
    created_at: str
    updated_at: str


class ContactList(BaseModel):
    items: list[Contact]
    total: int

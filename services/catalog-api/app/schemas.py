import datetime
from typing import Optional
from pydantic import BaseModel, Field

class ProductResponse(BaseModel):
    id: int
    name: str
    price: float
    stock: int

    class Config:
        from_attributes = True

class OrderCreate(BaseModel):
    product_id: int = Field(..., gt=0, description="Valid product ID")
    quantity: int = Field(default=1, gt=0, description="Quantity must be greater than zero")

class OrderCreateResponse(BaseModel):
    order_id: int

class OrderStatusResponse(BaseModel):
    id: int
    product_id: int
    quantity: int
    status: str
    created_at: datetime.datetime
    completed_at: Optional[datetime.datetime] = None

    class Config:
        from_attributes = True

class HealthResponse(BaseModel):
    status: str
    database: str
    queue: str

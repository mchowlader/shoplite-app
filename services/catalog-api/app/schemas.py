from datetime import datetime, timezone
from typing import Optional
from pydantic import BaseModel, Field, ConfigDict

class ProductResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    price: float
    stock: int

class OrderCreate(BaseModel):
    product_id: int = Field(..., gt=0, description="Valid product ID")
    quantity: int = Field(default=1, gt=0, description="Quantity must be greater than zero")

class OrderCreateResponse(BaseModel):
    order_id: int

class OrderStatusResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    product_id: int
    quantity: int
    status: str
    created_at: datetime
    completed_at: Optional[datetime] = None

class HealthResponse(BaseModel):
    status: str
    database: str
    queue: str


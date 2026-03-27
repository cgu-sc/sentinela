from pydantic import BaseModel
from typing import List, Optional

class TargetSummarySchema(BaseModel):
    id: str
    name: str
    status: str
    risk_level: str

class TargetResponse(BaseModel):
    targets: List[TargetSummarySchema]

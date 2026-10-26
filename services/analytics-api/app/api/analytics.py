from fastapi import APIRouter, Depends, HTTPException
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel
from app.db.clickhouse import clickhouse_client
from app.core.security import AnalyticsPrincipal, assert_resource_access, get_current_principal


router = APIRouter()


class StatsResponse(BaseModel):
    date: str
    campaign_id: Optional[int] = None
    ad_id: Optional[int] = None
    creative_id: Optional[int] = None
    total_impressions: int
    total_clicks: int
    total_conversions: int
    total_conversion_value: float
    last_click_conversions: int
    view_through_conversions: int
    total_fraud_events: int
    total_cost: float


@router.get("/ads", response_model=List[StatsResponse])
async def get_ad_stats(
    campaign_id: Optional[int] = None,
    ad_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    principal: AnalyticsPrincipal = Depends(get_current_principal),
):
    if ad_id is None and not principal.has("fraud.review"):
        raise HTTPException(status_code=422, detail="ad_id is required")
    if ad_id is not None:
        assert_resource_access("ads", ad_id, principal)
    try:
        results = clickhouse_client.get_ad_stats(
            campaign_id=campaign_id,
            ad_id=ad_id,
            start_date=start_date,
            end_date=end_date
        )
        
        return [
            StatsResponse(
                date=str(row[0]),
                campaign_id=row[1],
                ad_id=row[2],
                creative_id=row[3],
                total_impressions=row[4],
                total_clicks=row[5],
                total_conversions=row[6],
                total_conversion_value=float(row[7]),
                last_click_conversions=row[8],
                view_through_conversions=row[9],
                total_fraud_events=row[10],
                total_cost=float(row[11])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/campaigns", response_model=List[StatsResponse])
async def get_campaign_stats(
    campaign_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    principal: AnalyticsPrincipal = Depends(get_current_principal),
):
    if campaign_id is None and not principal.has("fraud.review"):
        raise HTTPException(status_code=422, detail="campaign_id is required")
    if campaign_id is not None:
        assert_resource_access("campaigns", campaign_id, principal)
    try:
        results = clickhouse_client.get_campaign_stats(
            campaign_id=campaign_id,
            start_date=start_date,
            end_date=end_date
        )
        
        return [
            StatsResponse(
                date=str(row[0]),
                campaign_id=row[1],
                total_impressions=row[2],
                total_clicks=row[3],
                total_conversions=row[4],
                total_conversion_value=float(row[5]),
                last_click_conversions=row[6],
                view_through_conversions=row[7],
                total_fraud_events=row[8],
                total_cost=float(row[9])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/creatives", response_model=List[StatsResponse])
async def get_creative_stats(
    creative_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    principal: AnalyticsPrincipal = Depends(get_current_principal),
):
    if creative_id is None and not principal.has("fraud.review"):
        raise HTTPException(status_code=422, detail="creative_id is required")
    if creative_id is not None:
        assert_resource_access("creatives", creative_id, principal)
    try:
        results = clickhouse_client.get_creative_stats(
            creative_id=creative_id,
            start_date=start_date,
            end_date=end_date
        )
        
        return [
            StatsResponse(
                date=str(row[0]),
                creative_id=row[1],
                total_impressions=row[2],
                total_clicks=row[3],
                total_conversions=row[4],
                total_conversion_value=float(row[5]),
                last_click_conversions=row[6],
                view_through_conversions=row[7],
                total_fraud_events=row[8],
                total_cost=float(row[9])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

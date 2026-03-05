from fastapi import APIRouter, HTTPException
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel
from app.db.clickhouse import clickhouse_client


router = APIRouter()


class StatsResponse(BaseModel):
    date: str
    campaign_id: int
    ad_id: Optional[int] = None
    creative_id: Optional[int] = None
    total_impressions: int
    total_clicks: int
    total_cost: float


@router.on_event("startup")
async def startup_event():
    clickhouse_client.connect()


@router.get("/ads", response_model=List[StatsResponse])
async def get_ad_stats(
    campaign_id: Optional[int] = None,
    ad_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None
):
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
                total_cost=float(row[6])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/campaigns", response_model=List[StatsResponse])
async def get_campaign_stats(
    campaign_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None
):
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
                total_cost=float(row[4])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/creatives", response_model=List[StatsResponse])
async def get_creative_stats(
    creative_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None
):
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
                total_cost=float(row[4])
            )
            for row in results
        ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
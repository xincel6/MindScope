from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from deps import get_current_user
from models import DiagnosisReport, MediaAsset, User
from schemas import ReportOut, ReportListItem, ReportListOut, StatsOut

router = APIRouter(prefix="/api")


@router.get("/report/{media_id}", response_model=list[ReportOut])
async def get_reports(
    media_id: int,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    result = await db.execute(
        select(DiagnosisReport)
        .where(DiagnosisReport.media_id == media_id)
        .order_by(DiagnosisReport.detected_at.desc())
    )
    reports = result.scalars().all()

    return [
        ReportOut(
            id=r.id,
            media_id=r.media_id,
            bdi_score=r.bdi_score,
            severity=r.severity.value,
            detected_at=r.detected_at.strftime("%Y-%m-%d %H:%M:%S"),
            inference_time_ms=r.inference_time_ms,
            notes=r.notes,
        )
        for r in reports
    ]


@router.get("/reports", response_model=ReportListOut)
async def list_reports(
    severity: Optional[str] = Query(None),
    media_type: Optional[str] = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    base = select(DiagnosisReport, MediaAsset.name, MediaAsset.type).join(
        MediaAsset, DiagnosisReport.media_id == MediaAsset.id
    )

    if severity:
        base = base.where(DiagnosisReport.severity == severity)
    if media_type:
        base = base.where(MediaAsset.type == media_type)

    # Count total
    count_q = select(func.count()).select_from(base.subquery())
    total = (await db.execute(count_q)).scalar() or 0

    # Fetch page
    offset = (page - 1) * limit
    q = base.order_by(DiagnosisReport.detected_at.desc()).offset(offset).limit(limit)
    result = await db.execute(q)
    rows = result.all()

    items = [
        ReportListItem(
            id=row.DiagnosisReport.id,
            media_id=row.DiagnosisReport.media_id,
            media_name=row.name,
            media_type=row.type.value,
            bdi_score=row.DiagnosisReport.bdi_score,
            severity=row.DiagnosisReport.severity.value,
            detected_at=row.DiagnosisReport.detected_at.strftime("%Y-%m-%d %H:%M:%S"),
            inference_time_ms=row.DiagnosisReport.inference_time_ms,
        )
        for row in rows
    ]

    return ReportListOut(items=items, total=total)


@router.get("/stats", response_model=StatsOut)
async def get_stats(
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
):
    # Total analyses
    total_analyses = (await db.execute(select(func.count(DiagnosisReport.id)))).scalar() or 0

    # Total media
    total_media = (await db.execute(select(func.count(MediaAsset.id)))).scalar() or 0

    # Severity distribution
    sev_result = await db.execute(
        select(DiagnosisReport.severity, func.count(DiagnosisReport.id))
        .group_by(DiagnosisReport.severity)
    )
    severity_distribution = {row[0].value: row[1] for row in sev_result.all()}
    for level in ["none", "mild", "moderate", "severe"]:
        severity_distribution.setdefault(level, 0)

    # Avg inference time
    avg_inf = (await db.execute(select(func.avg(DiagnosisReport.inference_time_ms)))).scalar()
    avg_inference_time_ms = round(avg_inf, 2) if avg_inf else 0.0

    # BDI trend (group by date)
    trend_result = await db.execute(
        select(
            func.date(DiagnosisReport.detected_at).label("date"),
            func.avg(DiagnosisReport.bdi_score).label("avg_score"),
        )
        .group_by(func.date(DiagnosisReport.detected_at))
        .order_by(text("date ASC"))
    )
    bdi_trend = [
        {"date": row[0], "avg_score": round(row[1], 1)} for row in trend_result.all()
    ]

    # Recent reports (top 10)
    recent_q = (
        select(DiagnosisReport, MediaAsset.name, MediaAsset.type)
        .join(MediaAsset, DiagnosisReport.media_id == MediaAsset.id)
        .order_by(DiagnosisReport.detected_at.desc())
        .limit(10)
    )
    recent_result = await db.execute(recent_q)
    recent_rows = recent_result.all()
    recent_reports = [
        ReportListItem(
            id=row.DiagnosisReport.id,
            media_id=row.DiagnosisReport.media_id,
            media_name=row.name,
            media_type=row.type.value,
            bdi_score=row.DiagnosisReport.bdi_score,
            severity=row.DiagnosisReport.severity.value,
            detected_at=row.DiagnosisReport.detected_at.strftime("%Y-%m-%d %H:%M:%S"),
            inference_time_ms=row.DiagnosisReport.inference_time_ms,
        )
        for row in recent_rows
    ]

    return StatsOut(
        total_analyses=total_analyses,
        total_media=total_media,
        severity_distribution=severity_distribution,
        avg_inference_time_ms=avg_inference_time_ms,
        bdi_trend=bdi_trend,
        recent_reports=recent_reports,
    )

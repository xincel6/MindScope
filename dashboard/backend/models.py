import datetime
from typing import Optional, List
from sqlalchemy import String, Float, Integer, DateTime, Enum as SAEnum, Text, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column, relationship
from database import Base
import enum


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    email: Mapped[Optional[str]] = mapped_column(String(128), unique=True, nullable=True)
    hashed_password: Mapped[str] = mapped_column(String(256), nullable=False)
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow
    )


class MediaType(str, enum.Enum):
    video = "video"
    image = "image"


class SeverityLevel(str, enum.Enum):
    none = "none"
    mild = "mild"
    moderate = "moderate"
    severe = "severe"


class MediaAsset(Base):
    __tablename__ = "media_assets"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(256), nullable=False)
    # 上传该素材的账号名；历史数据可能为 NULL
    uploader_name: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    # 所属患者名（素材库按患者筛选 / 命名）；历史数据可能为 NULL
    patient: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)
    file_path: Mapped[str] = mapped_column(String(512), nullable=False)
    type: Mapped[MediaType] = mapped_column(SAEnum(MediaType), nullable=False)
    thumbnail_url: Mapped[str] = mapped_column(String(512), default="")
    duration: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow
    )

    reports: Mapped[List["DiagnosisReport"]] = relationship(
        back_populates="media", cascade="all, delete-orphan"
    )


class DiagnosisReport(Base):
    __tablename__ = "diagnosis_reports"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    media_id: Mapped[int] = mapped_column(ForeignKey("media_assets.id"), nullable=False)
    media: Mapped[MediaAsset] = relationship(back_populates="reports")

    bdi_score: Mapped[float] = mapped_column(Float, nullable=False)
    severity: Mapped[SeverityLevel] = mapped_column(SAEnum(SeverityLevel), nullable=False)
    detected_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow
    )
    inference_time_ms: Mapped[float] = mapped_column(Float, default=0.0)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)


class EmailVerification(Base):
    """邮箱验证码 · 注册时证明"你控制这个邮箱"的一次性凭据。

    ★ 存的是 `sha256(email:code)` 单向哈希，**绝不存明文验证码**：
      库文件一旦泄露，明文码会让人直接注册任意邮箱的账号。
    ★ `attempts` 累计失败次数，满 5 次由服务层把记录标记为 consumed（作废），
      防止把 5 分钟有效期当成暴力破解窗口。
    ★ `consumed` 一码一用：校验通过立即置位，重放同样的码会因查不到有效记录而失败。
    ★ `purpose` 区分"注册"与"找回密码"两种用途，校验时按用途取码，
      避免两个流程的码互相顶掉（`register` / `reset`）。
    """

    __tablename__ = "email_verifications"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(128), nullable=False, index=True)
    purpose: Mapped[str] = mapped_column(String(16), default="register", nullable=False)
    code_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    consumed: Mapped[bool] = mapped_column(default=False, nullable=False)
    created_at: Mapped[datetime.datetime] = mapped_column(
        DateTime, default=datetime.datetime.utcnow, index=True
    )
    expires_at: Mapped[datetime.datetime] = mapped_column(DateTime, nullable=False)

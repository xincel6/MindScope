"""
验证码生命周期 · 生成、频率限制、校验、作废

────────────────── 为什么验证码存哈希 ──────────────────
验证码是"证明你控制这个邮箱"的凭据。库里存明文的话，任何能读到数据库的
人（备份泄露、SQL 注入、误开的管理接口）都能直接拿去注册任意邮箱的账号。
所以存 `sha256(email:code)` 单向哈希，校验时重算比对；库文件泄露也拿不到
可用验证码。加 email 做盐是为了防止两个邮箱拿到同一码时交叉比对。

────────────────── 为什么发信放在作废旧码之前 ──────────────────
顺序是「发信成功 → 才作废旧码、写新码」。反过来（先作废再发）一旦 SMTP
超时或拒发，用户手里就连一个可用验证码都没有了，只能再等 60 秒冷却。

────────────────── 策略常量 ──────────────────
全部集中在顶部，调参不用翻逻辑。
"""

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from models import EmailVerification
from services.email import EmailService

CODE_LENGTH = 6                      # 6 位数字，10^6 空间
CODE_TTL_MINUTES = 5                 # 有效期 5 分钟
RESEND_COOLDOWN_SECONDS = 60         # 同一邮箱 60 秒内禁止重发
MAX_ATTEMPTS = 5                     # 同一验证码最多试 5 次，超过作废


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _code_hash(email: str, code: str) -> str:
    return hashlib.sha256(f"{email.lower()}:{code}".encode("utf-8")).hexdigest()


def generate_code() -> str:
    """6 位数字验证码 · 定长补零。

    用 `secrets` 而不是 `random`：后者是梅森旋转，种子可预测、能反推序列；
    6 位码空间本就只有 10^6，生成器再可预测等于没有。
    """
    return f"{secrets.randbelow(10 ** CODE_LENGTH):0{CODE_LENGTH}d}"


class VerificationService:
    """验证码的发放与核验 · 路由层只调 issue / check 两个方法。"""

    @staticmethod
    async def issue(db: AsyncSession, email: str) -> None:
        """给邮箱发一个新验证码（同一邮箱同时只有一条有效码）。"""
        if not EmailService.available():
            # 明确失败而不是静默跳过，否则用户永远等不到邮件却不知道原因
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="服务端未配置邮件服务，暂时无法发送验证码",
            )

        now = _utcnow()

        # ① 冷却检查：看该邮箱最近一条记录（含已消费的），60 秒内不重发
        recent = (await db.execute(
            select(EmailVerification)
            .where(EmailVerification.email == email.lower())
            .order_by(EmailVerification.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()

        if recent is not None:
            elapsed = (now - recent.created_at).total_seconds()
            if elapsed < RESEND_COOLDOWN_SECONDS:
                wait = int(RESEND_COOLDOWN_SECONDS - elapsed) + 1
                raise HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail=f"发送太频繁，请 {wait} 秒后再试",
                )

        # ② 生成并发信 —— 放在作废旧码之前，发信失败不影响用户手上的旧码
        code = generate_code()
        await EmailService.send_verification_code(email, code, CODE_TTL_MINUTES)

        # ③ 发信成功才落库：作废该邮箱所有旧码，写入新码
        await db.execute(
            update(EmailVerification)
            .where(EmailVerification.email == email.lower(),
                   EmailVerification.consumed.is_(False))
            .values(consumed=True)
        )
        db.add(EmailVerification(
            email=email.lower(),
            code_hash=_code_hash(email, code),
            expires_at=now + timedelta(minutes=CODE_TTL_MINUTES),
            created_at=now,
        ))
        await db.commit()

    @staticmethod
    async def check(db: AsyncSession, email: str, code: str) -> None:
        """校验验证码 · 失败抛 400，成功则标记为已消费。"""
        record = (await db.execute(
            select(EmailVerification)
            .where(EmailVerification.email == email.lower(),
                   EmailVerification.consumed.is_(False))
            .order_by(EmailVerification.created_at.desc())
            .limit(1)
        )).scalar_one_or_none()

        # 统一话术：不区分"没有码"和"码不对"，避免被用来探测邮箱状态
        invalid = HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="验证码错误或已过期，请重新获取",
        )

        if record is None:
            raise invalid

        if _utcnow() > record.expires_at:
            raise invalid

        if record.attempts >= MAX_ATTEMPTS:
            # 试满 5 次直接作废，逼对方重新拿码，防止把 5 分钟窗口当爆破窗口
            record.consumed = True
            await db.commit()
            raise invalid

        # 恒定时间比对，避免时序侧信道
        if not hmac.compare_digest(_code_hash(email, code), record.code_hash):
            record.attempts += 1
            await db.commit()
            raise invalid

        record.consumed = True
        await db.commit()

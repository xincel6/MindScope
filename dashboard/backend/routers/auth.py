import re

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth_utils import create_access_token, hash_password, verify_password
from database import get_db
from deps import get_current_user
from models import User
from schemas import (
    MessageOut,
    ResetPasswordIn,
    SendCodeIn,
    TokenOut,
    UserLogin,
    UserOut,
    UserRegister,
)
from services.verification import PURPOSE_REGISTER, PURPOSE_RESET, VerificationService

router = APIRouter(prefix="/api/auth", tags=["auth"])

_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_\u4e00-\u9fa5]{3,32}$")

# 邮箱格式：够用即可，不追求 RFC 5322 完备（那需要 email-validator 依赖）。
# 真正判死刑的是验证码——格式只挡掉明显乱填的，减轻发信压力。
_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")

PASSWORD_MIN_LENGTH = 6

# 找回密码时"邮箱没注册"与"验证码不对"共用同一句话，避免被用来枚举注册邮箱
_RESET_INVALID = "验证码错误或已过期，请重新获取"


def _validate_username(username: str) -> str:
    u = username.strip()
    if not _USERNAME_RE.match(u):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="用户名需 3–32 位，仅支持字母、数字、下划线或中文",
        )
    return u


def _validate_email(email: str) -> str:
    """规范化并校验邮箱 · 统一转小写（库里唯一索引建在小写上，避免大小写绕过）。"""
    e = (email or "").strip().lower()
    if len(e) > 128 or not _EMAIL_RE.match(e):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="邮箱格式不正确",
        )
    return e


def _validate_password(password: str) -> str:
    """密码强度校验 · 返回空串表示通过，否则是给用户看的中文提示。

    规则（2026-10-21 起强制）：至少 6 位，且同时包含大写字母、小写字母、特殊字符。
    只卡"注册"和"重置"两条路，登录不卡 —— 否则老账密改不动的用户会被锁在门外。
    """
    if len(password) < PASSWORD_MIN_LENGTH:
        return f"密码至少 {PASSWORD_MIN_LENGTH} 位"
    missing: list[str] = []
    if not any(c.isupper() for c in password):
        missing.append("大写字母")
    if not any(c.islower() for c in password):
        missing.append("小写字母")
    # 数字不算"字符"：这里要的是符号位，!@#$%^&* 这类
    if all(c.isalnum() for c in password):
        missing.append("特殊字符（如 ! @ #）")
    if len(missing) > 0:
        return "密码需同时包含大写字母、小写字母和特殊字符，当前缺少：" + "、".join(missing)
    return ""


@router.post("/send-code", status_code=status.HTTP_202_ACCEPTED)
async def send_verification_code(body: SendCodeIn, db: AsyncSession = Depends(get_db)):
    """发送验证码 · purpose=register（注册）/ purpose=reset（找回密码）。

    ★ register 与 reset 对"邮箱是否已注册"的要求正好相反，所以分开处理：
      · register：已注册 → 409（避免给他人邮箱滥发邮件，也顺带告诉用户换一个）；
      · reset：未注册 → **静默返回 202**，不发信也不说破（防用户枚举）。
    """
    email = _validate_email(body.email)
    purpose = PURPOSE_RESET if body.purpose == PURPOSE_RESET else PURPOSE_REGISTER

    taken = await db.execute(select(User).where(User.email == email))
    user = taken.scalar_one_or_none()

    if purpose == PURPOSE_REGISTER:
        if user is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该邮箱已被注册")
    else:
        # 找回密码：邮箱必须已注册。没注册也回 202（不暴露"这个邮箱没有账号"），
        # 但**不发信** —— 给一个不存在的邮箱发码没有意义，还会被当成发信垃圾。
        if user is None:
            return {"message": "如果该邮箱已注册，验证码将在片刻后送达"}

    await VerificationService.issue(db, email, purpose)
    return {"message": "验证码已发送，5 分钟内有效"}


@router.post("/register", response_model=TokenOut)
async def register(body: UserRegister, db: AsyncSession = Depends(get_db)):
    username = _validate_username(body.username)
    email = _validate_email(body.email)
    password_error = _validate_password(body.password)
    if password_error:
        raise HTTPException(status_code=400, detail=password_error)

    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="用户名已存在")

    email_taken = await db.execute(select(User).where(User.email == email))
    if email_taken.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="邮箱已被注册")

    # 验证码核验：失败会抛 400（不区分"没有码/码不对/已过期"）
    await VerificationService.check(db, email, body.verification_code.strip(), PURPOSE_REGISTER)

    user = User(
        username=username,
        email=email,
        hashed_password=hash_password(body.password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    # 注册即登录：直接发 token，前端无需再走一次登录（原行为，保持不变）
    token = create_access_token(user.id, user.username)
    return TokenOut(access_token=token)


@router.post("/reset-password", response_model=MessageOut)
async def reset_password(body: ResetPasswordIn, db: AsyncSession = Depends(get_db)):
    """邮箱找回密码 · 流程：send-code(purpose=reset) → 本接口。

    ★ 校验顺序是先格式、再验证码、最后落库：验证码校验失败就绝不该改动密码。
    ★ 不主动失效已签发的 JWT（无黑名单机制）：知道旧密码的人仍能用到令牌自然过期。
      要立刻踢下线，需要引入 token 版本号或 Redis 黑名单，本期不做。
    """
    email = _validate_email(body.email)
    password_error = _validate_password(body.new_password)
    if password_error:
        raise HTTPException(status_code=400, detail=password_error)

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    # 与"验证码不对"同一句话：不告诉访客"这个邮箱有没有账号"
    if user is None:
        raise HTTPException(status_code=400, detail=_RESET_INVALID)

    await VerificationService.check(db, email, body.verification_code.strip(), PURPOSE_RESET)

    user.hashed_password = hash_password(body.new_password)
    await db.commit()
    return MessageOut(message="密码已重置，请使用新密码登录")


@router.post("/login", response_model=TokenOut)
async def login(body: UserLogin, db: AsyncSession = Depends(get_db)):
    username = body.username.strip()
    result = await db.execute(select(User).where(User.username == username))
    user = result.scalar_one_or_none()
    if not user or not verify_password(body.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    if not user.is_active:
        raise HTTPException(status_code=403, detail="账号已禁用")

    token = create_access_token(user.id, user.username)
    return TokenOut(access_token=token)


@router.get("/me", response_model=UserOut)
async def me(current_user: User = Depends(get_current_user)):
    return UserOut(
        id=current_user.id,
        username=current_user.username,
        email=current_user.email,
        created_at=current_user.created_at.strftime("%Y-%m-%d"),
    )

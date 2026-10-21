import re

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth_utils import create_access_token, hash_password, verify_password
from database import get_db
from deps import get_current_user
from models import User
from schemas import SendCodeIn, TokenOut, UserLogin, UserOut, UserRegister
from services.verification import VerificationService

router = APIRouter(prefix="/api/auth", tags=["auth"])

_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_\u4e00-\u9fa5]{3,32}$")

# 邮箱格式：够用即可，不追求 RFC 5322 完备（那需要 email-validator 依赖）。
# 真正判死刑的是验证码——格式只挡掉明显乱填的，减轻发信压力。
_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$")


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


@router.post("/send-code", status_code=status.HTTP_202_ACCEPTED)
async def send_verification_code(body: SendCodeIn, db: AsyncSession = Depends(get_db)):
    """发送注册验证码。

    ★ 故意不返回"该邮箱是否已注册"：那是用户枚举漏洞，
      注册流程在提交时才会提示邮箱被占用。
    """
    email = _validate_email(body.email)

    # 已注册的邮箱直接拒绝，避免给他人邮箱滥发邮件
    taken = await db.execute(select(User).where(User.email == email))
    if taken.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="该邮箱已被注册")

    await VerificationService.issue(db, email)
    return {"message": "验证码已发送，5 分钟内有效"}


@router.post("/register", response_model=TokenOut)
async def register(body: UserRegister, db: AsyncSession = Depends(get_db)):
    username = _validate_username(body.username)
    email = _validate_email(body.email)
    password = body.password
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="密码至少 6 位")

    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="用户名已存在")

    email_taken = await db.execute(select(User).where(User.email == email))
    if email_taken.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="邮箱已被注册")

    # 验证码核验：失败会抛 400（不区分"没有码/码不对/已过期"）
    await VerificationService.check(db, email, body.verification_code.strip())

    user = User(
        username=username,
        email=email,
        hashed_password=hash_password(password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    # 注册即登录：直接发 token，前端无需再走一次登录（原行为，保持不变）
    token = create_access_token(user.id, user.username)
    return TokenOut(access_token=token)


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

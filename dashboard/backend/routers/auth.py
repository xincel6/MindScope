import re

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from auth_utils import create_access_token, hash_password, verify_password
from database import get_db
from deps import get_current_user
from models import User
from schemas import TokenOut, UserLogin, UserOut, UserRegister

router = APIRouter(prefix="/api/auth", tags=["auth"])

_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_\u4e00-\u9fa5]{3,32}$")


def _validate_username(username: str) -> str:
    u = username.strip()
    if not _USERNAME_RE.match(u):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="用户名需 3–32 位，仅支持字母、数字、下划线或中文",
        )
    return u


@router.post("/register", response_model=TokenOut)
async def register(body: UserRegister, db: AsyncSession = Depends(get_db)):
    username = _validate_username(body.username)
    password = body.password
    if len(password) < 6:
        raise HTTPException(status_code=400, detail="密码至少 6 位")

    existing = await db.execute(select(User).where(User.username == username))
    if existing.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="用户名已存在")

    email = (body.email or "").strip() or None
    if email:
        email_taken = await db.execute(select(User).where(User.email == email))
        if email_taken.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="邮箱已被注册")

    user = User(
        username=username,
        email=email,
        hashed_password=hash_password(password),
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

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

import shutil
from pathlib import Path

from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase

from config import DATABASE_PATH, DATABASE_URL, DEMO_DB_PATH

engine = create_async_engine(DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def ensure_database(db_path: Path = DATABASE_PATH, demo_path: Path = DEMO_DB_PATH) -> bool:
    """首次运行时用仓库里的演示库初始化运行库。

    ★ 只在**运行库不存在**时复制一次；已存在就绝不覆盖。
      这样"克隆仓库 → 启动就能看到演示数据"的体验不变，
      而线上把 `DATABASE_PATH` 指到仓库外之后，git 操作再也碰不到它（BUG-26）。

    Returns: True = 本次做了初始化；False = 已有库 / 没有种子。
    """
    db_path = Path(db_path)
    if db_path.exists():
        return False
    demo_path = Path(demo_path)
    if not demo_path.is_file():
        return False
    db_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(demo_path, db_path)
    print(f"[database] 首次运行：已从演示库初始化 {db_path}")
    return True


async def get_db() -> AsyncSession:
    async with async_session() as session:
        yield session


async def init_db():
    # ★ 必须在第一次连接之前：SQLite 连接会顺手创建空文件，
    #   空文件存在后 ensure_database 就不会再复制种子了。
    ensure_database()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # create_all 不会给已存在的表补列；旧库在这里做一次轻量迁移。
        rows = (await conn.exec_driver_sql("PRAGMA table_info(media_assets)")).fetchall()
        columns = [row[1] for row in rows]
        if "uploader_name" not in columns:
            await conn.exec_driver_sql(
                "ALTER TABLE media_assets ADD COLUMN uploader_name VARCHAR(64)"
            )
        if "patient" not in columns:
            await conn.exec_driver_sql(
                "ALTER TABLE media_assets ADD COLUMN patient VARCHAR(64)"
            )
        # email_verifications 是 2026-10-21 新增的表，purpose 列随后补上：
        # 老库（表已存在但没有 purpose）在这里补一列，历史记录一律算 register。
        rows = (await conn.exec_driver_sql("PRAGMA table_info(email_verifications)")).fetchall()
        columns = [row[1] for row in rows]
        if "purpose" not in columns:
            await conn.exec_driver_sql(
                "ALTER TABLE email_verifications ADD COLUMN purpose VARCHAR(16) DEFAULT 'register'"
            )

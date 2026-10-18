from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from config import DATABASE_URL

engine = create_async_engine(DATABASE_URL, echo=False)
async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with async_session() as session:
        yield session


async def init_db():
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

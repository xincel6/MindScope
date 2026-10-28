"""
邮件服务 · 只负责「投递」

────────────────── 职责边界 ──────────────────
本模块**只做一件事：把内容发到指定邮箱**。不生成验证码、不查数据库、
不判断频率限制——那些属于 `services/verification.py` 的职责。
分开放的原因：投递是纯 IO（可能慢、可能失败），策略是可测的逻辑，
混在一起就没法单独mock掉 SMTP 做单元测试。

────────────────── 为什么用线程池 ──────────────────
`smtplib` 是阻塞 IO。在 async 路由里直接调用会卡住整个事件循环——
那一瞬间其它用户的请求全部挂起，直到 SMTP 超时。所以统一走
`asyncio.to_thread`。
"""

import asyncio
import ssl
import smtplib
from email.header import Header
from email.mime.text import MIMEText

from config import (
    SMTP_FROM,
    SMTP_FROM_NAME,
    SMTP_HOST,
    SMTP_PASSWORD,
    SMTP_PORT,
    SMTP_USE_SSL,
    SMTP_USER,
    smtp_configured,
)

SMTP_TIMEOUT_SECONDS = 15


def _smtp_send(to: str, subject: str, body: str) -> None:
    """阻塞式发信 · 只允许在 asyncio.to_thread 里调用（见模块 docstring）。"""
    message = MIMEText(body, "plain", "utf-8")
    message["Subject"] = Header(subject, "utf-8")
    message["From"] = f"{SMTP_FROM_NAME} <{SMTP_FROM}>"
    message["To"] = to

    context = ssl.create_default_context()
    if SMTP_USE_SSL:
        # 465：连接建立即 TLS（隐式 SSL）
        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT, context=context,
                              timeout=SMTP_TIMEOUT_SECONDS) as server:
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_FROM, [to], message.as_string())
    else:
        # 587：明文连接 → STARTTLS 升级 → 登录 → 发信
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=SMTP_TIMEOUT_SECONDS) as server:
            server.ehlo()
            server.starttls(context=context)
            server.ehlo()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.sendmail(SMTP_FROM, [to], message.as_string())


def _render_body(code: str, ttl_minutes: int, purpose: str) -> str:
    """纯文本邮件体 · 不用 HTML：渲染稳定，且被判垃圾邮件的概率更低。

    按 `purpose` 区分标题与正文：用户同时可能等着"注册码"和"重置码"，
    两封一模一样的邮件会让用户搞不清该把哪个码填到哪个框里。
    """
    if purpose == "reset":
        subject = "MindScope 密码重置验证码"
        lead = "您正在重置 MindScope 账号密码。"
        warn = (
            "如果这不是您本人的操作，请忽略本邮件 ——\n"
            "没有验证码，任何人都无法改动您的密码。\n"
        )
    else:
        subject = "MindScope 邮箱验证码"
        lead = "您正在注册 MindScope 账号。"
        warn = (
            "如果这不是您本人的操作，请忽略本邮件 ——\n"
            "没有验证码，任何人都无法用您的邮箱注册账号。\n"
        )
    return (
        f"【MindScope】{subject}\n"
        "\n"
        f"{lead}\n"
        f"您的验证码是：{code}\n"
        f"有效期 {ttl_minutes} 分钟，请尽快完成验证。\n"
        "\n"
        f"{warn}"
        "\n"
        "—— MindScope 抑郁筛查辅助系统\n"
    )


class EmailService:
    """SMTP 投递门面 · 路由层只跟这个类打交道。"""

    @staticmethod
    def available() -> bool:
        """三要素（host/user/password）是否齐全 · 供路由层决定返回 503 还是放行。"""
        return smtp_configured()

    @staticmethod
    async def send_verification_code(
        email: str, code: str, ttl_minutes: int, purpose: str = "register"
    ) -> None:
        """发送验证码邮件。

        未配置 SMTP 时抛 RuntimeError（**不静默跳过**）：
        否则用户以为收到了码，实际什么也没发，注册流程会莫名卡死。
        """
        if not smtp_configured():
            raise RuntimeError(
                "服务端未配置 SMTP，请在 .env 中设置 SMTP_HOST / SMTP_USER / SMTP_PASSWORD"
            )

        subject = "MindScope 密码重置验证码" if purpose == "reset" else "MindScope 邮箱验证码"
        await asyncio.to_thread(
            _smtp_send,
            email,
            subject,
            _render_body(code, ttl_minutes, purpose),
        )

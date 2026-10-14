"""
Text LLM service via Infini-AI MaaS (OpenAI-compatible API).

Usage:
    result = await call_llm("你是谁")
    result = await call_llm("总结", system_prompt="你是一个助手")
"""

import json
import http.client
from typing import Optional

from config import LLM_API_KEY, LLM_API_HOST, LLM_API_PATH, LLM_MODEL


async def call_llm(
    user_content: str,
    system_prompt: Optional[str] = None,
    max_tokens: int = 1024,
    temperature: float = 0.7,
) -> str:
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_content})

    payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": False,
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_API_KEY}",
    }

    try:
        conn = http.client.HTTPSConnection(LLM_API_HOST, timeout=60)
        conn.request("POST", LLM_API_PATH, json.dumps(payload), headers)
        res = conn.getresponse()
        data = res.read()
        result = json.loads(data.decode("utf-8"))
        return result["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"[llm] call failed: {e}")
        return ""


async def call_llm_stream(
    user_content: str,
    system_prompt: Optional[str] = None,
    max_tokens: int = 1024,
    temperature: float = 0.7,
) -> str:
    messages = []
    if system_prompt:
        messages.append({"role": "system", "content": system_prompt})
    messages.append({"role": "user", "content": user_content})

    payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True,
    }

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {LLM_API_KEY}",
    }

    full_content = ""
    try:
        conn = http.client.HTTPSConnection(LLM_API_HOST, timeout=120)
        conn.request("POST", LLM_API_PATH, json.dumps(payload), headers)
        res = conn.getresponse()
        buffer = b""
        while True:
            chunk = res.read(1)
            if not chunk:
                break
            buffer += chunk
            if buffer.endswith(b"\n\n"):
                for line in buffer.strip().split(b"\n"):
                    if not line.startswith(b"data: "):
                        continue
                    data_str = line[6:].decode("utf-8").strip()
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                        delta = data["choices"][0].get("delta", {})
                        if "content" in delta:
                            full_content += delta["content"]
                    except json.JSONDecodeError:
                        continue
                buffer = b""
        return full_content
    except Exception as e:
        print(f"[llm] stream call failed: {e}")
        return ""

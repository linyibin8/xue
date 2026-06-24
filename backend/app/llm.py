import base64
import mimetypes
from pathlib import Path

import httpx

from .config import Settings


def _image_part(path: Path) -> dict:
    mime = mimetypes.guess_type(path.name)[0] or "image/jpeg"
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    return {
        "type": "image_url",
        "image_url": {"url": f"data:{mime};base64,{encoded}"},
    }


async def analyze_images(settings: Settings, prompt: str, image_paths: list[Path]) -> str:
    content: list[dict] = [{"type": "text", "text": prompt}]
    content.extend(_image_part(path) for path in image_paths)
    payload = {
        "model": settings.llm_model,
        "messages": [
            {
                "role": "system",
                "content": (
                    "你是 知进伴学 的学习陪伴分析助手。请用中文输出，"
                    "优先识别页码、题号、题目文字、关键截图信息、解题思路和学生下一步建议。"
                ),
            },
            {"role": "user", "content": content},
        ],
        "temperature": 0.2,
        "max_tokens": 1800,
    }
    headers = {"Authorization": f"Bearer {settings.llm_api_key}"}
    async with httpx.AsyncClient(base_url=settings.llm_base_url, timeout=120) as client:
        response = await client.post("/chat/completions", json=payload, headers=headers)
        response.raise_for_status()
        data = response.json()
    return data["choices"][0]["message"]["content"]


import asyncio
import json
import shutil
import uuid
from pathlib import Path

from fastapi import BackgroundTasks, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles

from . import llm
from .config import get_settings
from .db import connect, init_db, utc_now

app = FastAPI(title="知进伴学")


@app.on_event("startup")
def startup() -> None:
    init_db()
    settings = get_settings()
    app.mount("/images", StaticFiles(directory=settings.data_dir / "images"), name="images")


def emit_log(message: str, *, session_id: str | None = None, device_id: str | None = None, level: str = "info", source: str = "backend") -> None:
    with connect() as conn:
        conn.execute(
            "INSERT INTO logs(session_id, device_id, level, source, message, created_at) VALUES(?, ?, ?, ?, ?, ?)",
            (session_id, device_id, level, source, message, utc_now()),
        )


def row_to_dict(row) -> dict:
    return dict(row) if row is not None else {}


async def save_upload(upload: UploadFile, session_id: str, kind: str, batch_id: str | None = None) -> tuple[str, str]:
    settings = get_settings()
    ext = Path(upload.filename or "capture.jpg").suffix.lower() or ".jpg"
    image_id = uuid.uuid4().hex
    filename = f"{session_id}_{batch_id or 'single'}_{image_id}{ext}"
    target = settings.data_dir / "images" / filename
    with target.open("wb") as out:
        shutil.copyfileobj(upload.file, out)
    with connect() as conn:
        conn.execute(
            """
            INSERT INTO images(id, session_id, batch_id, kind, filename, original_name, created_at)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            """,
            (image_id, session_id, batch_id, kind, filename, upload.filename or "", utc_now()),
        )
    return image_id, filename


async def run_analysis(analysis_id: str, session_id: str, batch_id: str | None, prompt: str, filenames: list[str], summarize: bool = False) -> None:
    settings = get_settings()
    image_paths = [settings.data_dir / "images" / name for name in filenames]
    emit_log(f"开始大模型解析：{len(image_paths)} 张图片", session_id=session_id)
    try:
        content = await llm.analyze_images(settings, prompt, image_paths)
        status = "done"
    except Exception as exc:
        content = f"大模型解析失败：{exc}"
        status = "failed"
        emit_log(content, session_id=session_id, level="error")
    now = utc_now()
    with connect() as conn:
        conn.execute(
            "UPDATE analyses SET status=?, content=?, updated_at=? WHERE id=?",
            (status, content, now, analysis_id),
        )
        if summarize:
            previous = conn.execute("SELECT summary FROM sessions WHERE id=?", (session_id,)).fetchone()
            merged = ((previous["summary"] if previous else "") + "\n\n" + content).strip()
            conn.execute(
                "UPDATE sessions SET summary=?, status=?, updated_at=? WHERE id=?",
                (merged, "analyzed" if status == "done" else "error", now, session_id),
            )
        else:
            conn.execute("UPDATE sessions SET status=?, updated_at=? WHERE id=?", (status, now, session_id))
    emit_log(f"解析完成：{status}", session_id=session_id)


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "xue"}


@app.get("/", response_class=HTMLResponse)
def dashboard() -> str:
    return (Path(__file__).parent / "static" / "dashboard.html").read_text(encoding="utf-8")


@app.get("/api/sessions")
def list_sessions() -> dict:
    with connect() as conn:
        sessions = [dict(row) for row in conn.execute("SELECT * FROM sessions ORDER BY created_at DESC LIMIT 100")]
    return {"sessions": sessions}


@app.get("/api/sessions/{session_id}")
def get_session(session_id: str) -> dict:
    with connect() as conn:
        session = conn.execute("SELECT * FROM sessions WHERE id=?", (session_id,)).fetchone()
        if not session:
            raise HTTPException(404, "session not found")
        images = [dict(row) for row in conn.execute("SELECT * FROM images WHERE session_id=? ORDER BY created_at", (session_id,))]
        analyses = [dict(row) for row in conn.execute("SELECT * FROM analyses WHERE session_id=? ORDER BY created_at", (session_id,))]
    return {"session": dict(session), "images": images, "analyses": analyses}


@app.post("/api/solve-single")
async def solve_single(
    background_tasks: BackgroundTasks,
    image: UploadFile = File(...),
    device_id: str = Form("iphone"),
    page_hint: str = Form(""),
    question_hint: str = Form(""),
) -> dict:
    session_id = uuid.uuid4().hex
    now = utc_now()
    with connect() as conn:
        conn.execute(
            "INSERT INTO sessions(id, device_id, mode, title, status, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)",
            (session_id, device_id, "single", "单张拍题解析", "uploaded", now, now),
        )
    _, filename = await save_upload(image, session_id, "single")
    analysis_id = uuid.uuid4().hex
    prompt = (
        f"请解析这张学生拍摄的课本/试卷照片。页码提示：{page_hint or '未知'}；题号提示：{question_hint or '未知'}。"
        "请输出：1. 识别到的页码和题号；2. 题目标题文字；3. 题目内容摘要；4. 分步解题指导；5. 容易错的点。"
    )
    with connect() as conn:
        conn.execute(
            "INSERT INTO analyses(id, session_id, scope, status, prompt, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)",
            (analysis_id, session_id, "single", "running", prompt, now, now),
        )
    emit_log("收到单张拍题图片，已进入同步解析流程", session_id=session_id, device_id=device_id)
    await run_analysis(analysis_id, session_id, None, prompt, [filename])
    return get_session(session_id)


@app.post("/api/sessions")
def create_session(device_id: str = Form("iphone"), mode: str = Form("burst"), title: str = Form("智能连拍学习回合")) -> dict:
    session_id = uuid.uuid4().hex
    now = utc_now()
    with connect() as conn:
        conn.execute(
            "INSERT INTO sessions(id, device_id, mode, title, status, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?)",
            (session_id, device_id, mode, title, "created", now, now),
        )
    emit_log("创建学习回合", session_id=session_id, device_id=device_id)
    return {"session_id": session_id}


@app.post("/api/sessions/{session_id}/batches")
async def upload_batch(
    session_id: str,
    background_tasks: BackgroundTasks,
    images: list[UploadFile] = File(...),
    device_id: str = Form("iphone"),
    environment: str = Form(""),
) -> dict:
    with connect() as conn:
        if not conn.execute("SELECT id FROM sessions WHERE id=?", (session_id,)).fetchone():
            raise HTTPException(404, "session not found")
    batch_id = uuid.uuid4().hex
    filenames = []
    for image in images:
        _, filename = await save_upload(image, session_id, "burst", batch_id)
        filenames.append(filename)
    now = utc_now()
    analysis_id = uuid.uuid4().hex
    prompt = (
        f"这是一个学习回合中的一批智能连拍照片，共 {len(filenames)} 张。环境信息：{environment or '未提供'}。"
        "请识别关键课本/试卷内容、学习行为线索、题目变化，并输出本批照片对学习报告有价值的信息。"
    )
    with connect() as conn:
        conn.execute(
            "INSERT INTO analyses(id, session_id, batch_id, scope, status, prompt, created_at, updated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
            (analysis_id, session_id, batch_id, "batch", "running", prompt, now, now),
        )
        conn.execute("UPDATE sessions SET status=?, updated_at=? WHERE id=?", ("analyzing", now, session_id))
    emit_log(f"收到智能连拍批次：{len(filenames)} 张", session_id=session_id, device_id=device_id)
    background_tasks.add_task(run_analysis, analysis_id, session_id, batch_id, prompt, filenames, True)
    return {"session_id": session_id, "batch_id": batch_id, "analysis_id": analysis_id, "image_count": len(filenames)}


@app.post("/api/logs")
async def ingest_log(request: Request) -> dict:
    body = await request.json()
    emit_log(
        str(body.get("message", "")),
        session_id=body.get("session_id"),
        device_id=body.get("device_id"),
        level=body.get("level", "info"),
        source=body.get("source", "ios"),
    )
    return {"ok": True}


@app.get("/api/logs")
def get_logs(session_id: str | None = None, after_id: int = 0) -> dict:
    sql = "SELECT * FROM logs WHERE id > ?"
    params: list = [after_id]
    if session_id:
        sql += " AND session_id = ?"
        params.append(session_id)
    sql += " ORDER BY id DESC LIMIT 200"
    with connect() as conn:
        logs = [dict(row) for row in conn.execute(sql, params)]
    return {"logs": list(reversed(logs))}


@app.get("/api/logs/stream")
async def stream_logs(session_id: str | None = None, after_id: int = 0) -> StreamingResponse:
    async def events():
        last_id = after_id
        while True:
            data = get_logs(session_id=session_id, after_id=last_id)["logs"]
            for item in data:
                last_id = max(last_id, item["id"])
                yield f"data: {json.dumps(item, ensure_ascii=False)}\n\n"
            await asyncio.sleep(1)

    return StreamingResponse(events(), media_type="text/event-stream")


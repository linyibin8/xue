# 知进伴学 (xue)

学生学习陪伴辅助工具：iPhone 拍题/智能连拍上传，后端同步展示图片、日志与大模型解析。

> 全新独立项目（基于 pai-codex 重构）。线上域名：https://xue.evowit.com

## 目录

- `backend/` FastAPI 后端、Web dashboard、LLM 解析、日志流
- `ios/` 原生 SwiftUI iOS App（知进伴学）
- `deploy/` nginx 反向代理配置

## 后端本地运行

```bash
cd backend
python -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8028 --reload
```

访问：

- Dashboard: http://127.0.0.1:8028/
- Health: http://127.0.0.1:8028/health

## 环境变量

- `XUE_DATA_DIR`: 数据目录，默认 `./data`
- `XUE_PUBLIC_BASE_URL`: 对外地址，默认 `https://xue.evowit.com`
- `XUE_LLM_BASE_URL`: OpenAI-compatible base URL，默认 `http://100.64.0.5:39000/v1`
- `XUE_LLM_API_KEY`: API Key，默认 `ollama`
- `XUE_LLM_MODEL`: 模型名，默认 `evowit-agent27b`

## 部署架构

- 后端容器常驻：`ydz@100.64.0.13`，端口 `8028`（docker compose）
- 反向代理：`vps-gz (159.75.178.237)` nginx → `http://100.64.0.13:8028`（走 tailscale 内网）
- 域名：`xue.evowit.com`（腾讯云 DNS，A 记录 → 159.75.178.237）

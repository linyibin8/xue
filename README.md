# 知进伴学 (xue)

学生学习陪伴辅助工具：iPhone 拍题/智能连拍/语音提问，后端同步展示图片、日志与大模型解析。线上：https://xue.evowit.com

## 目录

- `backend/` FastAPI 后端、Web dashboard、LLM 解析、日志流
- `ios/` 原生 SwiftUI iOS App

## 后端本地运行

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\pip install -r requirements.txt
.\.venv\Scripts\uvicorn app.main:app --host 0.0.0.0 --port 8028 --reload
```

访问：

- Dashboard: http://127.0.0.1:8028/
- Health: http://127.0.0.1:8028/health

## 环境变量

- `XUE_DATA_DIR`: 数据目录，默认 `./data`
- `XUE_LLM_BASE_URL`: OpenAI-compatible base URL，默认 `http://100.64.0.5:39000/v1`
- `XUE_LLM_API_KEY`: API Key，默认 `ollama`
- `XUE_LLM_MODEL`: 模型名，默认 `evowit-agent27b`


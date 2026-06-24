# xue Operations Roadmap

Updated: 2026-06-23

## Current Milestone

- GitHub milestone tag: `pre-account-system-milestone-20260623`
- Public domain target: `https://xue.evowit.com`
- Default LLM endpoint: `http://100.64.0.5:39000/v1`
- Backend host: `ydz@100.64.0.13`

## Account And Data Isolation

Data boundary is `account_id`.

- `accounts`: top-level tenant.
- `users`: login principals.
- `account_members`: membership and role in an account.
- `identity_profiles`: student, parent, teacher identities under one account.
- `sessions.account_id`: every learning session belongs to exactly one account.
- `sessions.student_profile_id`: a session can be tied to one student identity.
- memory/profile/model/log/task tables now carry `account_id` where they can be queried directly.

Knowledge-base partitioning should follow this rule:

- Student-private knowledge: learning sessions, images, QA, mistakes, review events, memory events, long-term profile.
- Account-shared knowledge: parent/teacher access to students in the same account.
- System knowledge: prompts, global product defaults, public model platform metadata.
- Never mix student profile summaries across accounts. Cross-student summaries inside one account must be explicit and role-gated.

## SQL And Redis Plan

SQLite remains the compatibility database for this milestone. MySQL is added to Docker Compose behind the `mysql` profile so it can be deployed without forcing an immediate ORM rewrite.

Recommended sequence:

1. Keep SQLite live while auth/domain/model APIs are stabilized.
2. Add a data access layer or SQLAlchemy models for new account-scoped tables first.
3. Migrate high-write tables next: `images`, `analyses`, `qa_events`, `task_runs`, `llm_usage_events`.
4. Move binary/image files to object storage later; keep DB storing metadata only.
5. Enable Redis for cache and queue state:
   - session overview cache
   - student profile cache
   - learning asset search cache
   - LLM queue/inflight state
   - idempotency keys for uploads

## Model Platform

Use LiteLLM Proxy as the model gateway. It is a mature open-source OpenAI-compatible gateway that can unify OpenAI, Anthropic, Gemini, Zhipu, and other providers.

Milestone implementation:

- `/api/model-platforms` exposes supported provider metadata.
- `/api/model-configs` stores account-level model configs.
- API keys are encrypted before storage and never returned by the API.
- Runtime uses the account default model config when present, and falls back to the system model on `100.64.0.5`.

Next implementation step:

- Run LiteLLM Proxy on `ydz@100.64.0.13`.
- Point `XUE_LLM_BASE_URL` to the LiteLLM proxy.
- Optionally map account model configs into LiteLLM virtual keys for centralized quotas and audit logs.
- Extend `llm_usage_events` with prompt/completion token counts from response `usage`.

## Operational Data Reset

Before public registration, clear existing generated history after backup:

```powershell
python scripts\clear_operational_data.py --data-dir backend\data --yes
```

For production on `ydz@100.64.0.13`, run the equivalent under:

```bash
cd /home/ydz/services/xue
python3 scripts/clear_operational_data.py --data-dir backend/data --yes
```

Use `--include-users` only if you want to wipe registered users and model configs too.

## Mobile Plan

- iOS/iPad: add login/register UI, token storage, student selector, model config screen.
- iPad: reuse iOS app with adaptive split-view layout and wider review/dashboard surfaces.
- Android: keep backend API stable; build native Android or Flutter/Kotlin client after auth and account APIs are stable.

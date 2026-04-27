from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
import uuid
import json
import os

# ----------------------------
# App (ONLY ONE)
# ----------------------------
app = FastAPI(title="FocusMate MVP API")

# ----------------------------
# CORS (Flutter Web needs this)
# ----------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # MVP ok
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------------------
# Storage files
# ----------------------------
USERS_FILE = "users.json"
DB = Path("db.json")


def load_users():
    if not os.path.exists(USERS_FILE):
        return []
    with open(USERS_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_users(users):
    with open(USERS_FILE, "w", encoding="utf-8") as f:
        json.dump(users, f, indent=2)


def _load_db():
    # ✅ ensure BOTH sessions + checkins exist
    if not DB.exists():
        return {"sessions": [], "checkins": []}

    data = json.loads(DB.read_text(encoding="utf-8"))

    if "sessions" not in data:
        data["sessions"] = []
    if "checkins" not in data:
        data["checkins"] = []

    return data


def _save_db(data):
    DB.write_text(json.dumps(data, indent=2), encoding="utf-8")


def utc_now_iso():
    return datetime.now(timezone.utc).isoformat()


def parse_iso(dt_str: str) -> datetime:
    # Handle "Z" or timezone-aware strings
    if dt_str.endswith("Z"):
        dt_str = dt_str.replace("Z", "+00:00")
    return datetime.fromisoformat(dt_str)


# ----------------------------
# Focus scoring (matches your Flutter logic)
# ----------------------------
def predict_focus(duration_seconds: int, idle_seconds: int) -> str:
    idle_ratio = idle_seconds / max(duration_seconds, 1)
    if idle_ratio < 0.05:
        return "high"
    elif idle_ratio < 0.15:
        return "moderate"
    return "low"


# ----------------------------
# Request models (JSON body)
# ----------------------------
class AuthRequest(BaseModel):
    email: str
    password: str


class StartReq(BaseModel):
    user_id: str
    goal: str
    planned_minutes: int
    distraction_budget: int = 3


class StopReq(BaseModel):
    session_id: str
    elapsed_seconds: int
    idle_seconds: int
    focus_prediction: str | None = None  # Flutter sends "High/Moderate/Low"
    distraction_count: int | None = 0
    goal_completed: bool = False


# ✅ NEW: Check-in request model
class CheckinReq(BaseModel):
    user_id: str
    session_id: str
    task: str
    focus_rating: int  # 1..5
    distraction: str   # "social", "chat", "tired", "other", "none"


# ----------------------------
# Check-in helpers
# ----------------------------
def save_checkin(req: CheckinReq):
    data = _load_db()
    data["checkins"].append({
        "user_id": req.user_id,
        "session_id": req.session_id,
        "task": req.task,
        "focus_rating": int(req.focus_rating),
        "distraction": req.distraction,
        "timestamp": utc_now_iso(),
    })
    _save_db(data)


def coach_suggestion(focus_rating: int, distraction: str) -> str:
    # Simple “AI coach” rules (good for MVP + demo)
    if distraction == "social":
        return "Quick fix: put phone away for 10 minutes. Micro-goal: finish 1 section before checking."
    if distraction == "chat":
        return "Try: a 5-minute deep focus sprint. Tell others you’ll reply after the sprint."
    if distraction == "tired":
        return "Try: 60-second stretch + water. Then do a tiny task (2 minutes) to restart momentum."
    if focus_rating <= 2:
        return "Low focus detected. Try a 2-minute micro-goal: write 3 bullet points, then continue."
    if focus_rating == 3:
        return "Moderate focus. Try: remove 1 distraction and set a 10-minute sprint goal."
    return "Nice focus! Keep going — next check-in will help you stay consistent."

def generate_reflection(elapsed_seconds, idle_seconds, distraction_count, goal_completed, planned_minutes):
    idle_ratio = idle_seconds / max(elapsed_seconds, 1)

    parts = []

    # Focus stability
    if idle_ratio < 0.10:
        parts.append("You maintained strong focus for most of the session.")
    elif idle_ratio < 0.25:
        parts.append("Your focus was moderate, with a few idle moments.")
    else:
        parts.append("Your focus dropped several times due to long idle periods.")

    # Distractions
    if distraction_count == 0:
        parts.append("Great job avoiding distractions — zero app switches!")
    elif distraction_count <= 3:
        parts.append(f"You had {distraction_count} distractions, but stayed mostly on track.")
    else:
        parts.append(f"You had {distraction_count} distractions, which affected your flow.")

    # Goal completion
    if goal_completed:
        parts.append("You completed your goal — excellent work.")
    else:
        parts.append("You didn’t complete your goal, but that’s okay. Try breaking it into smaller micro‑goals next time.")

    # Planned vs actual
    planned_seconds = planned_minutes * 60
    if elapsed_seconds > planned_seconds:
        parts.append("You worked longer than planned — great dedication.")
    elif elapsed_seconds < planned_seconds:
        parts.append("You stopped earlier than planned. Consider shorter sessions if this feels more natural.")

    return " ".join(parts)





# ----------------------------
# Routes
# ----------------------------
@app.get("/")
def root():
    return {"status": "Backend running"}


# ✅ JSON-body register
@app.post("/register")
def register(req: AuthRequest):
    users = load_users()

    if any(u["email"] == req.email for u in users):
        raise HTTPException(status_code=400, detail="User already exists")

    users.append({"email": req.email, "password": req.password})
    save_users(users)
    return {"message": "User registered successfully"}


# ✅ JSON-body login (fixes 422)
@app.post("/login")
def login(req: AuthRequest):
    users = load_users()
    for u in users:
        if u["email"] == req.email and u["password"] == req.password:
            return {
                "message": "Login successful",
                "user_id": u["email"]
            }

    raise HTTPException(status_code=401, detail="Invalid credentials")


@app.get("/should_autostart")
def should_autostart(user_id: str):
    data = _load_db()
    sessions = [s for s in data["sessions"] if s["user_id"] == user_id and s["end_time"]]

    if not sessions:
        return {"auto": True}

    last = max(sessions, key=lambda s: s["end_time"])
    last_time = parse_iso(last["end_time"])
    hours_since = (datetime.now(timezone.utc) - last_time).total_seconds() / 3600

    # simple rule: autostart if last study was > 2h ago
    return {"auto": hours_since > 2}


@app.post("/session/start")
def session_start(req: StartReq):
    data = _load_db()
    session_id = str(uuid.uuid4())

    data["sessions"].append({
        "user_id": req.user_id,
        "session_id": session_id,
        "start_time": utc_now_iso(),
        "end_time": None,
        "duration_seconds": None,
        "idle_seconds": None,
        "focus_pred": None,
        
        # Focus Contract
        "goal": req.goal,
        "planned_minutes": req.planned_minutes,
        "distraction_budget": req.distraction_budget,
        "distraction_count": 0,
        "goal_completed": None,

    })

    _save_db(data)
    return {"session_id": session_id}


# ✅ IMPORTANT: Flutter calls /session/stop
@app.post("/session/stop")
def stop_session(payload: dict):
    data = _load_db()

    session_id = payload.get("session_id")
    if not session_id:
        raise HTTPException(status_code=400, detail="Missing session_id")

    found = False

    for s in data["sessions"]:
        if s["session_id"] == session_id:
            s["duration_seconds"] = payload.get("elapsed_seconds", 0)
            s["idle_seconds"] = payload.get("idle_seconds", 0)
            s["focus_pred"] = payload.get("focus_prediction", "low")
            s["distraction_count"] = payload.get("distraction_count", 0)
            s["goal_completed"] = payload.get("goal_completed", False)
            s["end_time"] = datetime.now(timezone.utc).isoformat()
            found = True
            break

    if not found:
        raise HTTPException(status_code=404, detail="Session not found")

    _save_db(data)
    return {"status": "ok"}
    # Session reflection 
@app.post("/session/reflection")
def session_reflection(data: dict):
    reflection = generate_reflection(
        elapsed_seconds=data.get("elapsed_seconds", 0),
        idle_seconds=data.get("idle_seconds", 0),
        distraction_count=data.get("distraction_count", 0),
        goal_completed=data.get("goal_completed", False),
        planned_minutes=data.get("planned_minutes", 25),
    )

    return {"reflection": reflection}



# ✅ NEW: Save a focus check-in and return coach suggestion
@app.post("/checkin")
def checkin(req: CheckinReq):
    if req.focus_rating < 1 or req.focus_rating > 5:
        raise HTTPException(status_code=400, detail="focus_rating must be 1..5")

    save_checkin(req)
    suggestion = coach_suggestion(req.focus_rating, req.distraction)
    return {"message": "saved", "suggestion": suggestion}


# ✅ NEW: Top distraction today (for dashboard)
@app.get("/top_distraction")
def top_distraction(user_id: str):
    data = _load_db()
    today = datetime.now(timezone.utc).date()

    checkins = [
        c for c in data.get("checkins", [])
        if c["user_id"] == user_id and parse_iso(c["timestamp"]).date() == today
    ]

    if not checkins:
        return {"top": "none", "count": 0}

    counts = {}
    for c in checkins:
        d = c.get("distraction", "none")
        counts[d] = counts.get(d, 0) + 1

    top = max(counts, key=counts.get)
    return {"top": top, "count": counts[top]}


@app.get("/stats")
def stats(user_id: str):
    data = _load_db()
    sessions = [
        s for s in data["sessions"]
        if s["user_id"] == user_id and s["duration_seconds"] is not None
    ]

    total_sessions = len(sessions)
    total_time = sum(int(s["duration_seconds"]) for s in sessions)
    total_nudges_proxy = sum(1 for s in sessions if int(s.get("idle_seconds") or 0) > 60)
    
    total_distractions = sum(int(s.get("distraction_count")or 0) for s in sessions)
    completed = sum(1 for s in sessions if s.get("goal_completed") is True)
    completion_rate = round((completed / total_sessions) * 100,1) if total_sessions else 0.0

    return {
        "total_sessions": total_sessions,
        "total_study_seconds": total_time,
        "total_nudges_proxy": total_nudges_proxy,
        "total_distractions": total_distractions,
        "goal_completion_rate": completion_rate,
    }


@app.get("/weekly_stats")
def weekly_stats(user_id: str):
    data = _load_db()

    user_sessions = [
        s for s in data.get("sessions", [])
        if s.get("user_id") == user_id
        and s.get("end_time") is not None
        and s.get("duration_seconds") is not None
    ]

    week = {
        "mon": [],
        "tue": [],
        "wed": [],
        "thu": [],
        "fri": [],
        "sat": [],
        "sun": []
    }

    for s in user_sessions:
        try:
            dt = parse_iso(s["end_time"])
            day = dt.strftime("%a").lower()
            if day in week:
                week[day].append(s)
        except:
            continue

    def compute_focus(sessions):
        if not sessions:
            return 0

        total = sum(int(s.get("duration_seconds") or 0) for s in sessions)
        idle = sum(int(s.get("idle_seconds") or 0) for s in sessions)

        if total == 0:
            return 0

        ratio = 1 - (idle / total)

        if ratio > 0.75:
            return 2
        elif ratio > 0.5:
            return 1
        return 0

    return {
        "mon": compute_focus(week["mon"]),
        "tue": compute_focus(week["tue"]),
        "wed": compute_focus(week["wed"]),
        "thu": compute_focus(week["thu"]),
        "fri": compute_focus(week["fri"]),
        "sat": compute_focus(week["sat"]),
        "sun": compute_focus(week["sun"]),
    }
@app.get("/daily_summary")
def daily_summary(user_id: str):
    data = _load_db()
    today = datetime.now(timezone.utc).date()

    sessions_today = []
    for s in data["sessions"]:
        if s["user_id"] != user_id:
            continue
        if not s["end_time"] or s["duration_seconds"] is None:
            continue
        end_dt = parse_iso(s["end_time"]).date()
        if end_dt == today:
            sessions_today.append(s)

    if not sessions_today:
        return {
            "sessions": 0,
            "total_seconds": 0,
            "idle_seconds": 0,
            "avg_focus": 0,
            "nudge_count": 0,
            "distractions": 0,
            "completed_goals": 0,
            "summary": "No study activity recorded today.",
        }

    total_seconds = sum(int(s["duration_seconds"]) for s in sessions_today)
    idle_seconds = sum(int(s["idle_seconds"]) for s in sessions_today)
    nudge_count = sum(
        1 for s in sessions_today if int(s.get("idle_seconds") or 0) > 60
    )

    distractions = sum(
        int(s.get("distraction_count") or 0) for s in sessions_today
    )

    completed_goals = sum(
        1 for s in sessions_today if s.get("goal_completed") is True
    )

    avg_focus = 1 - (idle_seconds / total_seconds) if total_seconds > 0 else 0

    if avg_focus > 0.75:
        summary = "Strong focus today — great consistency."
    elif avg_focus > 0.5:
        summary = "Moderate focus today — some distractions but good effort."
    else:
        summary = "Focus was low today — consider shorter sessions or more breaks."

    return {
        "sessions": len(sessions_today),
        "total_seconds": total_seconds,
        "idle_seconds": idle_seconds,
        "avg_focus": round(avg_focus, 2),
        "nudge_count": nudge_count,
        "distractions": distractions,
        "completed_goals": completed_goals,
        "summary": summary,
    }
    
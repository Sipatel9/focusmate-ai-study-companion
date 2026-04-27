import json
from pathlib import Path

DB = Path("db.json")

def _load():
    if not DB.exists():
        return {"sessions": []}
    return json.loads(DB.read_text())

def _save(data):
    DB.write_text(json.dumps(data, indent=2))

def save_session_start(user_id, session_id, start_time):
    data = _load()
    data["sessions"].append({
        "user_id": user_id,
        "session_id": session_id,
        "start_time": start_time,
        "end_time": None,
        "duration_seconds": None,
        "idle_seconds": None
    })
    _save(data)

def save_session_end(user_id, session_id, end_time, duration_seconds, idle_seconds):
    data = _load()
    for s in data["sessions"]:
        if s["user_id"] == user_id and s["session_id"] == session_id:
            s["end_time"] = end_time
            s["duration_seconds"] = duration_seconds
            s["idle_seconds"] = idle_seconds
            break
    _save(data)

def get_stats(user_id):
    data = _load()
    sessions = [
        s for s in data["sessions"]
        if s["user_id"] == user_id and s["duration_seconds"] is not None
    ]
    total_sessions = len(sessions)
    total_time = sum(s["duration_seconds"] for s in sessions)
    total_nudges = sum(1 for s in sessions if (s["idle_seconds"] or 0) > 60)

    return {
        "total_sessions": total_sessions,
        "total_study_seconds": total_time,
        "total_nudges_proxy": total_nudges
    }

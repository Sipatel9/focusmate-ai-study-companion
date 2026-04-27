# FocusMate – Behaviour‑Driven Study & Focus Tracker

FocusMate is a cross‑platform study companion designed to help students improve focus, reduce distractions, and understand their study behaviour through data‑driven insights.  
The system tracks idle time, app switching, and session duration, then uses a lightweight ML model to generate a focus score and weekly analytics.

---

## 🚀 Features

### 📱 Frontend (Flutter)
- Tracks idle time, app switching, and session duration
- Clean, accessible UI with high‑contrast colours and readable fonts
- Simple start/stop session controls
- Weekly summary screen

### 🧠 Backend (FastAPI)
- Processes session data
- Runs ML model to generate focus score (high / moderate / low)
- Stores session history
- Generates weekly analytics (study time, idle time, distractions, average focus)

### 🤖 Machine Learning
- Simple regression model using:
  - idle seconds  
  - number of distractions  
  - session duration  
- Predicts a numeric focus score mapped to categories

---

## 🏗️ System Architecture


- Flutter handles UI + behaviour tracking  
- FastAPI handles analytics, ML, and data storage  
- Modular design for easy future upgrades (database, authentication, native detection)

---

## 📊 API Endpoints

### `POST /start-session`
Initialises a study session.

### `POST /end-session`
Sends session metrics → backend calculates:
- duration  
- idle time  
- distractions  
- focus score  
- weekly stats update  

### `GET /weekly-summary`
Returns aggregated analytics for the last 7 days.

---

## 🧪 Testing

Backend logic was validated by testing:
- focus score calculation  
- session processing  
- weekly analytics generation  

Example test:

```python
import unittest
from app.logic import calculate_focus_score

class TestFocusCalculation(unittest.TestCase):
    def test_high_focus(self):
        score = calculate_focus_score(10, 0, 60)
        self.assertGreaterEqual(score, 0.7)

    def test_low_focus(self):
        score = calculate_focus_score(300, 5, 30)
        self.assertLessEqual(score, 0.3)

if __name__ == "__main__":
    unittest.main()
---

## 📄 License

This project does not use an open-source license.  
All rights reserved.

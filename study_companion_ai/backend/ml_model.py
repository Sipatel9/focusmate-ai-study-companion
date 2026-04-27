import joblib
import numpy as np

_model = joblib.load("focus_model.joblib")

def predict_focus(duration: int, idle: int) -> str:
    X = np.array([[duration, idle]])
    pred = int(_model.predict(X)[0])
    return "high" if pred == 1 else "low"

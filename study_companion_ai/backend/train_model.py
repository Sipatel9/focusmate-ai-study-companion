import numpy as np
from sklearn.ensemble import RandomForestClassifier
import joblib

# Dummy training data
# [study_duration_seconds, idle_seconds]
X = np.array([
    [900, 10],
    [1200, 20],
    [1500, 30],
    [600, 200],
    [700, 180],
    [800, 250],
    [1800, 50],
    [2000, 40],
    [400, 220],
])

# 1 = high focus, 0 = low focus
y = np.array([1, 1, 1, 0, 0, 0, 1, 1, 0])

model = RandomForestClassifier(n_estimators=100, random_state=42)
model.fit(X, y)

joblib.dump(model, "focus_model.joblib")
print("Saved focus_model.joblib")

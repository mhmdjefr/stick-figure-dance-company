import os
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from pythonosc.udp_client import SimpleUDPClient

client = SimpleUDPClient("127.0.0.1", 12000)

model_path = os.path.join(os.path.dirname(__file__), "models", "pose_landmarker_lite.task")
options = vision.PoseLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path=model_path),
    running_mode=vision.RunningMode.VIDEO,
)
landmarker = vision.PoseLandmarker.create_from_options(options)

cap = cv2.VideoCapture(0)
start = time.monotonic()

while cap.isOpened():
    ok, frame = cap.read()
    if not ok:
        break

    # Mirror the frame first so the figure moves like a mirror image
    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

    # Timestamps must increase on every call in VIDEO mode
    ts_ms = int((time.monotonic() - start) * 1000)
    result = landmarker.detect_for_video(mp_image, ts_ms)

    if result.pose_landmarks:
        landmarks = result.pose_landmarks[0]  # first detected person
        data = []
        for lm in landmarks:
            data += [lm.x, lm.y, lm.z, lm.visibility]  # 33 landmarks x 4 floats
        client.send_message("/pose", data)

        h, w = frame.shape[:2]
        for lm in landmarks:
            cv2.circle(frame, (int(lm.x * w), int(lm.y * h)), 4, (0, 255, 0), -1)

    cv2.imshow("Vision (press q to quit)", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()

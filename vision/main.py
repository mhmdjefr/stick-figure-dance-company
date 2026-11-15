import math
import os
import time

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from pythonosc.udp_client import SimpleUDPClient

MAX_PEOPLE = 4
MAX_MATCH_DIST = 0.25  # max centroid jump between frames (normalized units)
MAX_MISSING = 15       # frames a track survives without a match

client = SimpleUDPClient("127.0.0.1", 12000)

model_path = os.path.join(os.path.dirname(__file__), "models", "pose_landmarker_lite.task")
options = vision.PoseLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path=model_path),
    running_mode=vision.RunningMode.VIDEO,
    num_poses=MAX_PEOPLE,
    min_pose_detection_confidence=0.5,
    min_pose_presence_confidence=0.5,
    min_tracking_confidence=0.5,
)
landmarker = vision.PoseLandmarker.create_from_options(options)

tracks = {}  # id -> {"pos": (x, y), "missing": int}
next_id = 0


def centroid(lms):
    # Average of shoulders and hips
    pts = [lms[11], lms[12], lms[23], lms[24]]
    return (sum(p.x for p in pts) / 4, sum(p.y for p in pts) / 4)


def torso_visible(lms):
    # Shoulders and hips must be clearly visible, otherwise skip this person
    return min(lms[i].visibility for i in (11, 12, 23, 24)) > 0.3


def assign_ids(centers):
    """Greedy nearest-centroid matching so each person keeps the same ID."""
    global next_id
    pairs = sorted(
        (math.dist(c, t["pos"]), tid, di)
        for di, c in enumerate(centers)
        for tid, t in tracks.items()
    )
    ids = [None] * len(centers)
    used = set()
    for dist, tid, di in pairs:
        if dist > MAX_MATCH_DIST:
            break
        if tid in used or ids[di] is not None:
            continue
        ids[di] = tid
        used.add(tid)

    for di, c in enumerate(centers):
        if ids[di] is None:
            ids[di] = next_id
            next_id += 1
        tracks[ids[di]] = {"pos": c, "missing": 0}

    for tid in list(tracks):
        if tid not in ids:
            tracks[tid]["missing"] += 1
            if tracks[tid]["missing"] > MAX_MISSING:
                del tracks[tid]
    return ids


cap = cv2.VideoCapture(0)
start = time.monotonic()

while cap.isOpened():
    ok, frame = cap.read()
    if not ok:
        break

    # Mirror the frame first so the figures move like a mirror image
    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

    # Timestamps must increase on every call in VIDEO mode
    ts_ms = int((time.monotonic() - start) * 1000)
    result = landmarker.detect_for_video(mp_image, ts_ms)

    people = result.pose_landmarks or []
    ids = assign_ids([centroid(p) for p in people])

    h, w = frame.shape[:2]
    for pid, landmarks in zip(ids, people):
        data = [pid]
        for lm in landmarks:
            data += [lm.x, lm.y, lm.z, lm.visibility]  # id + 33 landmarks x 4 floats
        client.send_message("/pose", data)

        for lm in landmarks:
            cv2.circle(frame, (int(lm.x * w), int(lm.y * h)), 4, (0, 255, 0), -1)
        cx, cy = tracks[pid]["pos"]
        cv2.putText(frame, f"ID {pid}", (int(cx * w), int(cy * h)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 255), 2)

    cv2.imshow("Vision (press q to quit)", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()

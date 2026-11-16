import math
import os
import time

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision
from pythonosc.udp_client import SimpleUDPClient

MAX_PEOPLE = 4
MAX_MATCH_DIST = 0.25   # max centroid jump between frames (normalized units)
MAX_MISSING = 15        # frames a track survives without a match
SEND_MASK = True        # green silhouette in the preview (costs some FPS)
PREVIEW_SIZE = (160, 120)
PREVIEW_EVERY = 2       # send a preview frame every N frames
MAX_JPEG_BYTES = 8500   # macOS drops UDP datagrams above ~9 KB

client = SimpleUDPClient("127.0.0.1", 12000)

model_path = os.path.join(os.path.dirname(__file__), "models", "pose_landmarker_lite.task")
options = vision.PoseLandmarkerOptions(
    base_options=mp_python.BaseOptions(model_asset_path=model_path),
    running_mode=vision.RunningMode.VIDEO,
    num_poses=MAX_PEOPLE,
    min_pose_detection_confidence=0.5,
    min_pose_presence_confidence=0.5,
    min_tracking_confidence=0.5,
    output_segmentation_masks=SEND_MASK,
)
landmarker = vision.PoseLandmarker.create_from_options(options)

tracks = {}  # id -> {"pos": (x, y), "missing": int}
next_id = 0


def centroid(lms):
    # Average of shoulders and hips
    pts = [lms[11], lms[12], lms[23], lms[24]]
    return (sum(p.x for p in pts) / 4, sum(p.y for p in pts) / 4)


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


def make_preview(frame, masks):
    """Small JPEG of the camera frame with a green silhouette over detected people."""
    small = cv2.resize(frame, PREVIEW_SIZE)
    if masks:
        m = np.maximum.reduce([np.squeeze(x.numpy_view()) for x in masks])
        m = cv2.resize(m, PREVIEW_SIZE) > 0.5
        green = np.array([0, 255, 0], dtype=np.float32)  # BGR
        small[m] = (0.4 * small[m] + 0.6 * green).astype(np.uint8)
    ok, buf = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 50])
    return buf.tobytes() if ok else None


cap = cv2.VideoCapture(0)
start = time.monotonic()
frame_no = 0
print("Running. Press Ctrl+C to stop.")

try:
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

        for pid, landmarks in zip(ids, people):
            data = [pid]
            for lm in landmarks:
                data += [lm.x, lm.y, lm.z, lm.visibility]  # id + 33 landmarks x 4 floats
            client.send_message("/pose", data)

        frame_no += 1
        if frame_no % PREVIEW_EVERY == 0:
            jpg = make_preview(frame, result.segmentation_masks if SEND_MASK else None)
            if jpg is not None and len(jpg) <= MAX_JPEG_BYTES:
                client.send_message("/frame", jpg)
except KeyboardInterrupt:
    pass
finally:
    cap.release()

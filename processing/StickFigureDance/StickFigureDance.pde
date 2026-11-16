import oscP5.*;
import processing.sound.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.*;

OscP5 osc;
// oscEvent runs on another thread, so use a thread-safe map
ConcurrentHashMap<Integer, Figure> figures = new ConcurrentHashMap<Integer, Figure>();
color[] palette;
boolean cloneMode = false;
boolean delayOn = true;
final float VIS_MIN = 0.5; // min landmark visibility to draw a body part

final int NUM_SLOTS = 12;      // total clones on the floor
float[] slotX = new float[NUM_SLOTS];
float[] slotZ = new float[NUM_SLOTS];

float floorY; // y of the dance floor in world space
final float FLOOR_HALF_W = 450;
final float FLOOR_HALF_D = 300;

SoundFile song;
Amplitude amp;
boolean hasMusic = false;
float level = 0;   // smoothed music volume
float peak = 0.01; // slowly decaying peak, used to normalize the volume

void setup() {
  size(960, 720, P3D); // 4:3, same aspect ratio as a 640x480 webcam
  floorY = height * 0.75;
  osc = new OscP5(this, 12000);
  palette = new color[] { color(230, 60, 60), color(40, 120, 230), color(40, 170, 90), color(240, 160, 20) };

  // Fixed dance floor slots: 4 columns x 3 rows with some random jitter
  Random r = new Random(42);
  for (int i = 0; i < NUM_SLOTS; i++) {
    int col = i % 4;
    int row = i / 4;
    slotX[i] = width / 2.0 + (col - 1.5) * 220 + (r.nextFloat() - 0.5) * 90;
    slotZ[i] = (row - 1) * 200 + (r.nextFloat() - 0.5) * 80;
  }

  // Load music only if the file exists, so the sketch still runs without it
  if (new File(dataPath("music.mp3")).exists()) {
    song = new SoundFile(this, "music.mp3");
    amp = new Amplitude(this);
    amp.input(song);
    hasMusic = true;
  }
}

void draw() {
  background(255);

  if (hasMusic) {
    level = lerp(level, amp.analyze(), 0.2);
    peak = max(max(peak * 0.998, level), 0.01);
  }

  // Drop stale figures; keep only people whose shoulders are visible
  ArrayList<Integer> ids = new ArrayList<Integer>();
  for (Integer id : figures.keySet()) {
    Figure f = figures.get(id);
    if (f == null) continue;
    if (millis() - f.lastSeen > 500) {
      figures.remove(id);
    } else if (f.valid()) {
      ids.add(id);
    }
  }
  Collections.sort(ids);

  if (cloneMode) {
    // 3D scene: camera looks down at the floor from the front
    camera(width / 2.0, floorY - 450, 900, width / 2.0, floorY, 0, 0, 1, 0);
    drawFloor();

    // Slots are shared round-robin between people, so the total stays at NUM_SLOTS
    int n = ids.size();
    for (int j = 0; j < n; j++) {
      Figure f = figures.get(ids.get(j));
      if (f == null) continue;
      int i = 0;
      for (int s = j; s < NUM_SLOTS; s += n) {
        int delay = delayOn ? f.cloneDelay[i] : 0;
        f.displayClone(slotX[s], slotZ[s], f.cloneScale[i], f.cloneCol[i], delay);
        i++;
      }
    }
  } else {
    // Default camera maps the z=0 plane to pixel coordinates (2D-like view)
    camera();
    for (Integer id : ids) {
      Figure f = figures.get(id);
      if (f != null) f.displayLive();
    }
  }

  // HUD on top, in screen space
  camera();
  hint(DISABLE_DEPTH_TEST);
  drawHud(ids.size());
  hint(ENABLE_DEPTH_TEST);
}

void drawFloor() {
  noStroke();
  fill(128);
  beginShape(QUADS);
  vertex(width / 2.0 - FLOOR_HALF_W, floorY, -FLOOR_HALF_D);
  vertex(width / 2.0 + FLOOR_HALF_W, floorY, -FLOOR_HALF_D);
  vertex(width / 2.0 + FLOOR_HALF_W, floorY, FLOOR_HALF_D);
  vertex(width / 2.0 - FLOOR_HALF_W, floorY, FLOOR_HALF_D);
  endShape();
}

void drawHud(int people) {
  fill(150);
  noStroke();
  textAlign(LEFT, BASELINE);
  text("C: clone mode | D: clone delay (" + (delayOn ? "on" : "off") + ") | SPACE: play/pause music | people: " + people, 10, 20);

  if (hasMusic) {
    // Volume meter (debug), normalized to the recent peak
    float w = constrain(level / peak, 0, 1) * (width - 20);
    fill(220);
    rect(10, height - 24, width - 20, 10);
    fill(40, 120, 230);
    rect(10, height - 24, w, 10);
    fill(150);
    text(song.isPlaying() ? "music: playing" : "music: paused", 10, height - 32);
  } else {
    fill(200, 60, 60);
    text("music.mp3 not found in data/ folder", 10, height - 12);
  }
}

void keyPressed() {
  if (key == 'c' || key == 'C') cloneMode = !cloneMode;
  if (key == 'd' || key == 'D') delayOn = !delayOn;
  if (key == ' ' && hasMusic) {
    if (song.isPlaying()) song.pause();
    else song.loop();
  }
}

void oscEvent(OscMessage msg) {
  if (!msg.checkAddrPattern("/pose")) return;
  if (msg.arguments().length < 1 + 33 * 4) return;
  int id = msg.get(0).intValue();
  Figure f = figures.get(id);
  if (f == null) {
    f = new Figure(id, palette[id % palette.length]);
    figures.put(id, f);
  }
  f.update(msg);
}

// One snapshot of all 33 landmarks (never modified after it is created)
class Pose {
  float[] x = new float[33];
  float[] y = new float[33];
  float[] v = new float[33];
  int t; // timestamp in ms
}

class Figure {
  int id;
  color c;
  int lastSeen;
  boolean fresh = true;
  Pose cur = new Pose();

  // Ring buffer of recent poses, used to replay delayed movement on clones
  final int HIST = 120;
  Pose[] hist = new Pose[HIST];
  int head = 0; // next write index

  // Per-clone look: random size, color and delay
  float[] cloneScale = new float[NUM_SLOTS];
  color[] cloneCol = new color[NUM_SLOTS];
  int[] cloneDelay = new int[NUM_SLOTS];

  Figure(int id, color c) {
    this.id = id;
    this.c = c;
    Random r = new Random(id * 7919L + 13);
    for (int i = 0; i < NUM_SLOTS; i++) {
      cloneScale[i] = 0.8 + r.nextFloat() * 0.5;
      cloneCol[i] = color(60 + r.nextInt(196), 60 + r.nextInt(196), 60 + r.nextInt(196));
      cloneDelay[i] = (i == 0) ? 0 : r.nextInt(1200);
    }
  }

  void update(OscMessage msg) {
    Pose np = new Pose();
    for (int i = 0; i < 33; i++) {
      float nx = msg.get(1 + i * 4).floatValue();
      float ny = msg.get(1 + i * 4 + 1).floatValue();
      // Light smoothing to reduce jitter; snap on the first frame
      np.x[i] = fresh ? nx : lerp(cur.x[i], nx, 0.5);
      np.y[i] = fresh ? ny : lerp(cur.y[i], ny, 0.5);
      np.v[i] = msg.get(1 + i * 4 + 3).floatValue();
    }
    np.t = millis();
    cur = np;
    hist[head] = np;
    head = (head + 1) % HIST;
    fresh = false;
    lastSeen = millis();
  }

  // Newest pose that is at least delayMs old (or the oldest one we have)
  Pose poseAt(int delayMs) {
    if (delayMs <= 0) return cur;
    int target = millis() - delayMs;
    int h = head;
    Pose oldest = cur;
    for (int k = 1; k <= HIST; k++) {
      Pose p = hist[((h - k) % HIST + HIST) % HIST];
      if (p == null) break;
      oldest = p;
      if (p.t <= target) return p;
    }
    return oldest;
  }

  // A person counts only if both shoulders are visible
  boolean valid() {
    return cur.v[11] > VIS_MIN && cur.v[12] > VIS_MIN;
  }

  PVector pt(Pose p, int i) {
    return new PVector(map(p.x[i], 0, 1, 0, width), map(p.y[i], 0, 1, 0, height));
  }

  void bone(Pose p, int a, int b) {
    if (p.v[a] < VIS_MIN || p.v[b] < VIS_MIN) return; // skip low-confidence joints
    PVector pa = pt(p, a);
    PVector pb = pt(p, b);
    line(pa.x, pa.y, pb.x, pb.y);
  }

  // Draws the figure where the person actually is on screen
  void displayLive() {
    stroke(c);
    strokeWeight(4);
    fill(c);
    drawBody(cur);
  }

  // Stands a (possibly delayed) copy on the floor at world (wx, floorY, wz)
  void displayClone(float wx, float wz, float scl, color col, int delayMs) {
    Pose p = poseAt(delayMs);
    if (p.v[11] < VIS_MIN || p.v[12] < VIS_MIN) return;
    PVector neck = PVector.lerp(pt(p, 11), pt(p, 12), 0.5);
    float shoulderW = PVector.dist(pt(p, 11), pt(p, 12));
    if (shoulderW < 10) return;
    float k = scl * 60 / shoulderW;

    pushMatrix();
    // The neck sits about 210 units above the floor, so a full body reaches the floor
    translate(wx, floorY - 210 * scl, wz);
    scale(k);
    translate(-neck.x, -neck.y);
    stroke(col);
    strokeWeight(4 / k);
    fill(col);
    drawBody(p);
    popMatrix();
  }

  void drawBody(Pose p) {
    // Arms (each bone is skipped if either end is not visible)
    bone(p, 11, 12); bone(p, 11, 13); bone(p, 13, 15); bone(p, 12, 14); bone(p, 14, 16);

    // Torso and legs only when both hips are visible
    if (p.v[23] > VIS_MIN && p.v[24] > VIS_MIN) {
      bone(p, 23, 24); bone(p, 23, 25); bone(p, 25, 27); bone(p, 24, 26); bone(p, 26, 28);
      // MediaPipe has no neck/torso landmark, so compute them
      PVector neck = PVector.lerp(pt(p, 11), pt(p, 12), 0.5);
      PVector hip = PVector.lerp(pt(p, 23), pt(p, 24), 0.5);
      line(neck.x, neck.y, hip.x, hip.y);
    }

    // Head sized relative to shoulder width, joined to the shoulders by a neck line
    if (p.v[0] > VIS_MIN) {
      PVector nose = pt(p, 0);
      PVector shoulderMid = PVector.lerp(pt(p, 11), pt(p, 12), 0.5);
      line(shoulderMid.x, shoulderMid.y, nose.x, nose.y);
      float r = PVector.dist(pt(p, 11), pt(p, 12)) * 0.35;
      ellipse(nose.x, nose.y, r * 2, r * 2);
    }
  }
}

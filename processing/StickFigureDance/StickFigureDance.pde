import oscP5.*;
import processing.sound.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.*;

OscP5 osc;
// oscEvent runs on another thread, so use a thread-safe map
ConcurrentHashMap<Integer, Figure> figures = new ConcurrentHashMap<Integer, Figure>();
color[] palette;
boolean cloneMode = false;
float[] cloneScale = {0.5, 0.65, 0.45};
final float VIS_MIN = 0.5; // min landmark visibility to draw a body part

SoundFile song;
Amplitude amp;
boolean hasMusic = false;
float level = 0; // smoothed music volume, roughly 0..1

void setup() {
  size(960, 720); // 4:3, same aspect ratio as a 640x480 webcam
  osc = new OscP5(this, 12000);
  palette = new color[] { color(230, 60, 60), color(40, 120, 230), color(40, 170, 90), color(240, 160, 20) };

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
    // Dance floor: clones sit in fixed slots spread across the screen
    int total = ids.size() * cloneScale.length;
    int k = 0;
    for (Integer id : ids) {
      Figure f = figures.get(id);
      if (f == null) continue;
      for (int i = 0; i < cloneScale.length; i++) {
        float sx = width * (k + 1) / (total + 1.0);
        color col = lerpColor(f.c, palette[(f.id + i + 1) % palette.length], 0.6);
        f.displayClone(sx, height * 0.35, cloneScale[i], col);
        k++;
      }
    }
  } else {
    for (Integer id : ids) {
      Figure f = figures.get(id);
      if (f != null) f.displayLive();
    }
  }

  drawHud(ids.size());
}

void drawHud(int people) {
  fill(150);
  noStroke();
  textAlign(LEFT, BASELINE);
  text("C: clone mode | SPACE: play/pause music | people: " + people, 10, 20);

  if (hasMusic) {
    // Volume meter (debug), amplitude values are small so scale them up
    float w = constrain(level * 4, 0, 1) * (width - 20);
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

class Figure {
  int id;
  color c;
  int lastSeen;
  boolean fresh = true;
  float[] lx = new float[33];
  float[] ly = new float[33];
  float[] vis = new float[33];

  Figure(int id, color c) {
    this.id = id;
    this.c = c;
  }

  void update(OscMessage msg) {
    for (int i = 0; i < 33; i++) {
      float nx = msg.get(1 + i * 4).floatValue();
      float ny = msg.get(1 + i * 4 + 1).floatValue();
      // Light smoothing to reduce jitter; snap on the first frame
      lx[i] = fresh ? nx : lerp(lx[i], nx, 0.5);
      ly[i] = fresh ? ny : lerp(ly[i], ny, 0.5);
      vis[i] = msg.get(1 + i * 4 + 3).floatValue();
    }
    fresh = false;
    lastSeen = millis();
  }

  // A person counts only if both shoulders are visible
  boolean valid() {
    return vis[11] > VIS_MIN && vis[12] > VIS_MIN;
  }

  boolean hipsVisible() {
    return vis[23] > VIS_MIN && vis[24] > VIS_MIN;
  }

  PVector p(int i) {
    return new PVector(map(lx[i], 0, 1, 0, width), map(ly[i], 0, 1, 0, height));
  }

  void bone(int a, int b) {
    if (vis[a] < VIS_MIN || vis[b] < VIS_MIN) return; // skip low-confidence joints
    PVector pa = p(a);
    PVector pb = p(b);
    line(pa.x, pa.y, pb.x, pb.y);
  }

  // Draws the figure where the person actually is on screen
  void displayLive() {
    stroke(c);
    strokeWeight(4);
    noFill();
    drawBody();
  }

  // Draws the figure with its neck at (sx, sy), scaled by shoulder width
  void displayClone(float sx, float sy, float scl, color col) {
    PVector neck = PVector.lerp(p(11), p(12), 0.5);
    float shoulderW = PVector.dist(p(11), p(12));
    if (shoulderW < 10) return;
    float k = scl * 110 / shoulderW;

    pushMatrix();
    translate(sx, sy);
    scale(k);
    translate(-neck.x, -neck.y);
    stroke(col);
    strokeWeight(4 / k);
    noFill();
    drawBody();
    popMatrix();
  }

  void drawBody() {
    // Arms (each bone is skipped if either end is not visible)
    bone(11, 12); bone(11, 13); bone(13, 15); bone(12, 14); bone(14, 16);

    // Torso and legs only when both hips are visible
    if (hipsVisible()) {
      bone(23, 24); bone(23, 25); bone(25, 27); bone(24, 26); bone(26, 28);
      // MediaPipe has no neck/torso landmark, so compute them
      PVector neck = PVector.lerp(p(11), p(12), 0.5);
      PVector hip = PVector.lerp(p(23), p(24), 0.5);
      line(neck.x, neck.y, hip.x, hip.y);
    }

    // Head sized relative to shoulder width
    if (vis[0] > VIS_MIN) {
      PVector nose = p(0);
      float r = PVector.dist(p(11), p(12)) * 0.35;
      ellipse(nose.x, nose.y, r * 2, r * 2);
    }
  }
}

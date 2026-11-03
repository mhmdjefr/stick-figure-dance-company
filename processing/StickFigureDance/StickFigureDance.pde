import oscP5.*;

final int N = 33;           // MediaPipe landmark count
final int MAX_DELAY = 90;   // frames kept in history

OscP5 osc;
int lastMsg = -10000;
float[] curX = new float[N];
float[] curY = new float[N];
float[] curV = new float[N];

// Each snapshot: x[33], y[33], visibility[33] packed in one array
ArrayList<float[]> history = new ArrayList<float[]>();
Dancer[] dancers;

void setup() {
  size(960, 720);
  frameRate(30); // roughly matches webcam FPS, so 1 frame ~ 1 pose update
  osc = new OscP5(this, 12000);

  // delay (frames), x offset (px), scale, color
  dancers = new Dancer[] {
    new Dancer(0, 0, 1.0, color(0)),
    new Dancer(15, -380, 0.6, color(220, 60, 60)),
    new Dancer(30, 380, 0.6, color(60, 120, 220)),
    new Dancer(45, -200, 0.4, color(60, 170, 90)),
    new Dancer(60, 200, 0.4, color(230, 150, 30))
  };
}

void draw() {
  background(255);

  // No recent data: user left the frame, drop stale history
  if (millis() - lastMsg > 500) {
    history.clear();
    return;
  }

  float[] snap = new float[N * 3];
  for (int i = 0; i < N; i++) {
    snap[i] = curX[i];
    snap[N + i] = curY[i];
    snap[2 * N + i] = curV[i];
  }
  history.add(snap);
  if (history.size() > MAX_DELAY + 1) history.remove(0);

  for (Dancer d : dancers) {
    int idx = history.size() - 1 - d.delay;
    if (idx >= 0) d.display(history.get(idx));
  }
}

void oscEvent(OscMessage msg) {
  if (!msg.checkAddrPattern("/pose")) return;
  if (msg.arguments().length < N * 4) return;
  for (int i = 0; i < N; i++) {
    // Light smoothing to reduce jitter
    curX[i] = lerp(curX[i], msg.get(i * 4).floatValue(), 0.5);
    curY[i] = lerp(curY[i], msg.get(i * 4 + 1).floatValue(), 0.5);
    curV[i] = msg.get(i * 4 + 3).floatValue();
  }
  lastMsg = millis();
}

class Dancer {
  int delay;
  float offsetX, s;
  color c;

  Dancer(int delay, float offsetX, float s, color c) {
    this.delay = delay;
    this.offsetX = offsetX;
    this.s = s;
    this.c = c;
  }

  PVector pt(float[] f, int i) {
    return new PVector(map(f[i], 0, 1, 0, width), map(f[N + i], 0, 1, 0, height));
  }

  boolean ok(float[] f, int i) {
    // Confident AND inside the frame (MediaPipe guesses off-screen joints)
    return f[2 * N + i] >= 0.5
        && f[i] > 0 && f[i] < 1
        && f[N + i] > 0 && f[N + i] < 1;
  }

  void bone(float[] f, int a, int b) {
    if (!ok(f, a) || !ok(f, b)) return;
    PVector pa = pt(f, a);
    PVector pb = pt(f, b);
    line(pa.x, pa.y, pb.x, pb.y);
  }

  void display(float[] f) {
    pushMatrix();
    translate(width / 2 + offsetX, height / 2);
    scale(s);
    translate(-width / 2, -height / 2);
    stroke(c);
    strokeWeight(4 / s); // keep line thickness the same after scaling
    noFill();

    bone(f, 11, 12); bone(f, 11, 13); bone(f, 13, 15);
    bone(f, 12, 14); bone(f, 14, 16);
    bone(f, 23, 24); bone(f, 23, 25); bone(f, 25, 27);
    bone(f, 24, 26); bone(f, 26, 28);

    // Neck, torso, head: computed because MediaPipe has no such landmarks
    if (ok(f, 11) && ok(f, 12)) {
      PVector neck = PVector.lerp(pt(f, 11), pt(f, 12), 0.5);
      if (ok(f, 23) && ok(f, 24)) {
        PVector hip = PVector.lerp(pt(f, 23), pt(f, 24), 0.5);
        line(neck.x, neck.y, hip.x, hip.y);
      }
      if (ok(f, 0)) {
        PVector nose = pt(f, 0);
        float r = PVector.dist(pt(f, 11), pt(f, 12)) * 0.3;
        ellipse(nose.x, nose.y, r * 2, r * 2);
        line(neck.x, neck.y, nose.x, nose.y + r); // connect head to neck
      }
    }
    popMatrix();
  }
}

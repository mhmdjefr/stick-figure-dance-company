import oscP5.*;
import java.util.concurrent.ConcurrentHashMap;

OscP5 osc;
// oscEvent runs on another thread, so use a thread-safe map
ConcurrentHashMap<Integer, Figure> figures = new ConcurrentHashMap<Integer, Figure>();
color[] palette;
boolean cloneMode = false;
float[] cloneScale = {0.5, 0.65, 0.45};

void setup() {
  size(960, 720); // 4:3, same aspect ratio as a 640x480 webcam
  osc = new OscP5(this, 12000);
  palette = new color[] { color(230, 60, 60), color(40, 120, 230), color(40, 170, 90), color(240, 160, 20) };
}

void draw() {
  background(255);

  for (Integer id : figures.keySet()) {
    Figure f = figures.get(id);
    // Drop figures that stopped sending data (person left the frame)
    if (millis() - f.lastSeen > 500) {
      figures.remove(id);
      continue;
    }
    if (cloneMode) {
      // Book-style company: clone the same dancer with varied color, size and position
      for (int i = 0; i < cloneScale.length; i++) {
        float cx = (i - (cloneScale.length - 1) / 2.0) * 300;
        color c = lerpColor(f.c, palette[(f.id + i + 1) % palette.length], 0.6);
        f.display(cx, cloneScale[i], c);
      }
    } else {
      f.display(0, 1, f.c);
    }
  }

  fill(150);
  text("press C: toggle clone mode | people: " + figures.size(), 10, 20);
}

void keyPressed() {
  if (key == 'c' || key == 'C') cloneMode = !cloneMode;
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

  PVector p(int i) {
    return new PVector(map(lx[i], 0, 1, 0, width), map(ly[i], 0, 1, 0, height));
  }

  void bone(int a, int b) {
    if (vis[a] < 0.5 || vis[b] < 0.5) return; // skip low-confidence joints
    PVector pa = p(a);
    PVector pb = p(b);
    line(pa.x, pa.y, pb.x, pb.y);
  }

  // Draws scaled around the screen center, shifted by dx
  void display(float dx, float scl, color col) {
    pushMatrix();
    translate(width / 2 + dx, height / 2);
    scale(scl);
    translate(-width / 2, -height / 2);

    stroke(col);
    strokeWeight(4 / scl);
    noFill();

    // Arms
    bone(11, 12); bone(11, 13); bone(13, 15); bone(12, 14); bone(14, 16);
    // Legs
    bone(23, 24); bone(23, 25); bone(25, 27); bone(24, 26); bone(26, 28);

    // MediaPipe has no neck/torso landmark, so compute them
    PVector neck = PVector.lerp(p(11), p(12), 0.5);
    PVector hip = PVector.lerp(p(23), p(24), 0.5);
    line(neck.x, neck.y, hip.x, hip.y);

    // Head sized relative to shoulder width
    PVector nose = p(0);
    float r = PVector.dist(p(11), p(12)) * 0.35;
    ellipse(nose.x, nose.y, r * 2, r * 2);
    popMatrix();
  }
}

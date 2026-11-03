import oscP5.*;

OscP5 osc;
float[] lx = new float[33];
float[] ly = new float[33];
float[] vis = new float[33];
int lastMsg = -10000;

void setup() {
  size(960, 720); // 4:3, same aspect ratio as a 640x480 webcam
  osc = new OscP5(this, 12000);
}

void draw() {
  background(255);
  // Hide the figure if no data arrived recently (user left the frame)
  if (millis() - lastMsg > 500) return;

  stroke(0);
  strokeWeight(4);
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

void oscEvent(OscMessage msg) {
  if (!msg.checkAddrPattern("/pose")) return;
  if (msg.arguments().length < 33 * 4) return;
  for (int i = 0; i < 33; i++) {
    // Light smoothing to reduce jitter
    lx[i] = lerp(lx[i], msg.get(i * 4).floatValue(), 0.5);
    ly[i] = lerp(ly[i], msg.get(i * 4 + 1).floatValue(), 0.5);
    vis[i] = msg.get(i * 4 + 3).floatValue();
  }
  lastMsg = millis();
}

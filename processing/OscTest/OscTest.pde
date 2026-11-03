import oscP5.*;

OscP5 osc;
float x = 0.5;
float y = 0.5;

void setup() {
  size(640, 480);
  osc = new OscP5(this, 12000);
}

void draw() {
  background(255);
  fill(0);
  // Map normalized values to screen pixels
  ellipse(map(x, 0, 1, 0, width), map(y, 0, 1, 0, height), 30, 30);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/test")) {
    x = msg.get(0).floatValue();
    y = msg.get(1).floatValue();
  }
}

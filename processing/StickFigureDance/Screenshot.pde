// Press S to save a PNG into the repo's assets/ folder
boolean shotRequested = false;
String shotMsg = "";
int shotMsgUntil = 0;

void keyReleased() {
  if (key == 's' || key == 'S') shotRequested = true;
}

void handleScreenshot() {
  if (shotRequested) {
    shotRequested = false;
    String name = "shot-" + year() + nf(month(), 2) + nf(day(), 2) + "-"
      + nf(hour(), 2) + nf(minute(), 2) + nf(second(), 2) + ".png";
    save(sketchPath("../../assets/" + name));
    shotMsg = "saved assets/" + name;
    shotMsgUntil = millis() + 2500;
    println(shotMsg);
  }
  // Confirmation text is drawn after the capture, so it is not in the image
  if (millis() < shotMsgUntil) {
    hint(DISABLE_DEPTH_TEST);
    fill(40, 170, 90);
    noStroke();
    textAlign(LEFT, BASELINE);
    text(shotMsg, 10, height - 44);
    hint(ENABLE_DEPTH_TEST);
  }
}

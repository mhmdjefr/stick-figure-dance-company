// Camera preview with person silhouette, received from the Python vision module
PImage preview;
boolean hasPreview = false;
int lastFrameMs = -10000;

void receiveFrame(OscMessage msg) {
  byte[] data = msg.get(0).blobValue();
  PImage img = decodeJpeg(data);
  if (img != null) {
    preview = img;
    hasPreview = true;
    lastFrameMs = millis();
  }
}

PImage decodeJpeg(byte[] data) {
  try {
    java.awt.image.BufferedImage bi = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(data));
    if (bi == null) return null;
    PImage img = new PImage(bi.getWidth(), bi.getHeight(), RGB);
    bi.getRGB(0, 0, img.width, img.height, img.pixels, 0, img.width);
    img.updatePixels();
    return img;
  } catch (Exception e) {
    return null;
  }
}

void drawPreview() {
  // Hide the preview if frames stopped arriving
  if (!hasPreview || millis() - lastFrameMs > 1000) return;
  image(preview, 10, 30, 240, 180);
  noFill();
  stroke(150);
  strokeWeight(1);
  rect(10, 30, 240, 180);
}

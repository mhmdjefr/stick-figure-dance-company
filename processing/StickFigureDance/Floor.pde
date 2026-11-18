// Disco dance floor: colored square tiles whose hue cycles over time
// and whose brightness follows the music volume
final int TILES_X = 8;
final int TILES_Z = 6;

void drawDanceFloor() {
  noStroke();
  float tw = 2 * FLOOR_HALF_W / TILES_X;
  float td = 2 * FLOOR_HALF_D / TILES_Z;
  float energy = hasMusic ? constrain(level / peak, 0, 1) : 0;
  float t = millis() / 1000.0;
  float inset = 3; // small gap between tiles

  colorMode(HSB, 360, 100, 100);
  for (int i = 0; i < TILES_X; i++) {
    for (int j = 0; j < TILES_Z; j++) {
      float hue = (i * 31 + j * 47 + t * 40) % 360;
      float bright = 55 + 20 * ((i + j) % 2) + 25 * energy;
      fill(hue, 70, constrain(bright, 0, 100));

      float x0 = width / 2.0 - FLOOR_HALF_W + i * tw + inset;
      float x1 = x0 + tw - 2 * inset;
      float z0 = -FLOOR_HALF_D + j * td + inset;
      float z1 = z0 + td - 2 * inset;
      beginShape(QUADS);
      vertex(x0, floorY, z0);
      vertex(x1, floorY, z0);
      vertex(x1, floorY, z1);
      vertex(x0, floorY, z1);
      endShape();
    }
  }
  colorMode(RGB, 255); // restore, other code uses RGB colors
}

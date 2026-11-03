import math
import time
from pythonosc.udp_client import SimpleUDPClient

client = SimpleUDPClient("127.0.0.1", 12000)
t = 0.0
while True:
    # Normalized coordinates (0.0 - 1.0), same range MediaPipe uses
    x = 0.5 + 0.3 * math.cos(t)
    y = 0.5 + 0.3 * math.sin(t)
    client.send_message("/test", [x, y])
    t += 0.1
    time.sleep(1 / 30)

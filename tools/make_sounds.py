"""Generate tiny UI sound effects as WAV files (no downloads needed).
- tap.wav:     short soft click for button presses
- toggle.wav:  slightly higher blip for switches/tabs
- success.wav: two-tone chime for connected / cast started
- error.wav:   low soft buzz for failures
16-bit mono 22050Hz, each < 1s.
"""
import math, struct, wave
from pathlib import Path

SR = 22050
OUT = Path(__file__).resolve().parents[1] / "assets" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)

def tone(freq, ms, vol=0.5, slide_to=None):
    n = int(SR * ms / 1000)
    out = []
    for i in range(n):
        f = freq if slide_to is None else freq + (slide_to - freq) * i / n
        env = min(1.0, i / (SR * 0.008)) * (1 - i / n)  # quick fade in/out
        out.append(int(32767 * vol * env * math.sin(2 * math.pi * f * i / SR)))
    return out

def save(name, samples):
    with wave.open(str(OUT / name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(struct.pack(f"<{len(samples)}h", *samples))
    print("wrote", name, f"{len(samples)/SR:.2f}s")

save("tap.wav", tone(880, 60, 0.35, slide_to=660))
save("toggle.wav", tone(660, 70, 0.35, slide_to=990))
save("success.wav", tone(660, 120, 0.4) + tone(990, 180, 0.4))
save("error.wav", tone(220, 220, 0.4, slide_to=160))
print("OK ->", OUT)

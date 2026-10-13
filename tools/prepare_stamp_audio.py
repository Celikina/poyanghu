"""Extract one stamp from Sonilo's freely licensed library recording."""
from pathlib import Path
import argparse
import wave
import numpy as np

parser = argparse.ArgumentParser()
parser.add_argument('source', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
with wave.open(str(args.source), 'rb') as source:
    assert source.getsampwidth() == 2, 'Expected 16-bit PCM source'
    rate = source.getframerate()
    channels = source.getnchannels()
    samples = np.frombuffer(source.readframes(source.getnframes()), dtype='<i2').astype(np.float64)
    samples = samples.reshape(-1, channels).mean(axis=1)[:round(rate * 0.23)]
# First press only; short endpoint fades avoid clicks without adding more impacts.
samples *= 1.8
attack = round(rate * 0.001)
release = round(rate * 0.025)
samples[:attack] *= np.linspace(0, 1, attack)
samples[-release:] *= np.linspace(1, 0, release)
assert np.max(np.abs(samples)) < 32767, 'Do not clip the stamp'
args.output.parent.mkdir(parents=True, exist_ok=True)
with wave.open(str(args.output), 'wb') as output:
    output.setnchannels(1)
    output.setsampwidth(2)
    output.setframerate(rate)
    output.writeframes(np.round(samples).astype('<i2').tobytes())
print(f'STAMP_AUDIO duration={len(samples)/rate:.3f}s peak={np.max(np.abs(samples))/32768:.3f}')

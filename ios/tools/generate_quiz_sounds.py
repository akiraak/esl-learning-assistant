#!/usr/bin/env python3
"""単語クイズの正誤フィードバック効果音を生成する。

出力: ../ESLLearningAssistant/Resources/Sounds/{correct,wrong}.caf
  - correct.caf: 明るい上昇アルペジオのベルチャイム（気持ちいい音）
  - wrong.caf : 低めで柔らかい短いブリップ（それとない音）

numpy 非依存（標準ライブラリのみ）。16bit PCM mono WAV を書き出し、
afconvert で CAF(LEI16) に変換する。再生成したいときはこのスクリプトを実行する。

    python3 tools/generate_quiz_sounds.py
"""
import math
import os
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "ESLLearningAssistant", "Resources", "Sounds")


def _blank(seconds):
    return [0.0] * int(SAMPLE_RATE * seconds)


def _add_tone(buf, start_s, freq, dur_s, amp, decay=18.0, harmonics=((1, 1.0),), attack_s=0.004):
    """buf（float配列）に、指数減衰する正弦波（＋倍音）を start_s から加算する。"""
    start = int(SAMPLE_RATE * start_s)
    n = int(SAMPLE_RATE * dur_s)
    attack = max(1, int(SAMPLE_RATE * attack_s))
    for i in range(n):
        idx = start + i
        if idx >= len(buf):
            break
        t = i / SAMPLE_RATE
        env = math.exp(-decay * t)
        if i < attack:  # クリック防止の短いフェードイン
            env *= i / attack
        sample = 0.0
        for mult, hamp in harmonics:
            sample += hamp * math.sin(2 * math.pi * freq * mult * t)
        buf[idx] += amp * env * sample


def _normalize(buf, peak=0.9):
    hi = max((abs(x) for x in buf), default=0.0)
    if hi <= 0:
        return buf
    gain = peak / hi
    return [x * gain for x in buf]


def _write_wav(path, buf):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for x in buf:
            v = int(max(-1.0, min(1.0, x)) * 32767)
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))


def _to_caf(wav_path, caf_path):
    subprocess.run(
        ["afconvert", "-f", "caff", "-d", "LEI16", wav_path, caf_path],
        check=True,
    )
    os.remove(wav_path)


def build_correct():
    # C6 E6 G6 C7 の上昇アルペジオ。各音を少しずつ遅らせてベル風に重ねる
    buf = _blank(0.85)
    notes = [1046.50, 1318.51, 1567.98, 2093.00]
    harmonics = ((1, 1.0), (2, 0.35), (3, 0.12))  # ベル寄りの倍音
    for i, f in enumerate(notes):
        _add_tone(buf, start_s=0.09 * i, freq=f, dur_s=0.75, amp=0.5,
                  decay=6.5, harmonics=harmonics)
    return _normalize(buf, peak=0.85)


def build_wrong():
    # 低め・柔らかい下降2音。控えめに（音量低め・短め・倍音少なめ）
    buf = _blank(0.42)
    soft = ((1, 1.0), (2, 0.08))
    _add_tone(buf, start_s=0.00, freq=311.13, dur_s=0.22, amp=0.5,
              decay=16.0, harmonics=soft, attack_s=0.008)  # E♭4
    _add_tone(buf, start_s=0.12, freq=233.08, dur_s=0.28, amp=0.5,
              decay=14.0, harmonics=soft, attack_s=0.008)  # B♭3
    return _normalize(buf, peak=0.5)  # 正解より小さめでそれとなく


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, builder in (("correct", build_correct), ("wrong", build_wrong)):
        wav_path = os.path.join(OUT_DIR, name + ".wav")
        caf_path = os.path.join(OUT_DIR, name + ".caf")
        _write_wav(wav_path, builder())
        _to_caf(wav_path, caf_path)
        print("generated", os.path.relpath(caf_path))


if __name__ == "__main__":
    main()

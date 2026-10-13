# -*- coding: utf-8 -*-
"""《保卫鄱阳湖》算分动画音效生成器（纯 Python 标准库，零第三方依赖）

用法：
    python tools/make_ding.py

产出：
    assets/audio/ding.wav   「叮」——逐张弹分 / 指标结算
    assets/audio/land.wav   「啪」——甩牌落桌的闷响
    assets/audio/deal.wav   「唰」——发牌时牌角离堆、牌面切风的声音（见文件末尾 DEAL 一段）

⚠ 生成后必须在 Godot 编辑器里打开一次工程（或跑 godot --headless --import），
   让它产出 .import 文件；否则导出包里没有音效。

音色设计要点（改参数前先读这段）：
  · 基频选 E6(1318.5Hz)：明亮但不刺耳，比 C6 更有「叮」的穿透力，
    又不像 2kHz 那样在连击时聒噪。
  · 上滑(chirp)：击槌瞬间频率抬高 5.5% 再回落，τ=18ms。
    这是「叮」和正弦波「哔」的分界线 —— 去掉它就成了电子音。
  · 分音刻意用非谐比率(1.00/2.01/2.99/4.17/5.43)：产生金属/木琴质感。
    若改成整倍数(1/2/3/4/5)会立刻变成风琴音，失去「敲击」感。
  · 高次分音衰减更快(11→36/s)，符合真实物理的阻尼规律。
  · 6ms 白噪模拟击槌接触瞬间，给声音「实体感」；固定随机种子保证
    每次生成字节完全一致（否则每次跑都产生 git diff，无法入库比对）。
"""

import array
import math
import os
import random
import sys
import wave

SR = 44100          # 采样率：Godot 原生格式，零重采样
PEAK = 0.89         # 归一化峰值（留约 1dB 余量，多声叠播不削顶）
ATTACK = 0.002      # 2ms 起音斜坡（防起始爆音）
FADE = 0.010        # 10ms 收尾淡出（防截断爆音）

# 音色配方
#   f0        基频 Hz
#   dur       总时长 秒
#   chirp     上滑比例（正=起手抬高，负=起手压低）
#   chirp_t   上滑时间常数 秒
#   noise     击槌噪声幅度
#   noise_t   噪声衰减时间常数 秒
#   partials  [(频率比, 振幅, 衰减系数 1/s), ...]
RECIPES = {
    # 逐张弹分 / 指标结算的「叮」
    "ding": dict(
        f0=1318.5, dur=0.30, chirp=0.055, chirp_t=0.018,
        noise=0.10, noise_t=0.006,
        partials=[(1.00, 1.00, 11.0), (2.01, 0.42, 15.0), (2.99, 0.22, 21.0),
                  (4.17, 0.13, 28.0), (5.43, 0.07, 36.0)],
    ),
    # 甩牌落桌的闷响
    "land": dict(
        f0=170.0, dur=0.16, chirp=-0.030, chirp_t=0.010,
        noise=0.55, noise_t=0.010,
        partials=[(1.00, 1.00, 34.0), (1.58, 0.34, 46.0), (2.42, 0.14, 62.0)],
    ),
}


def synth(recipe, seed=20260928):
    """按配方合成一段归一化到 [-1, 1] 的单声道浮点样本。"""
    n = int(SR * recipe["dur"])
    out = [0.0] * n
    chirp = recipe["chirp"]
    chirp_t = recipe["chirp_t"]

    # 分音叠加。用相位积分而不是直接 sin(2πft)，才能做频率滑移。
    for ratio, amp, decay in recipe["partials"]:
        f0 = recipe["f0"] * ratio
        phase = 0.0
        for i in range(n):
            t = i / SR
            inst_f = f0 * (1.0 + chirp * math.exp(-t / chirp_t))
            phase += 2.0 * math.pi * inst_f / SR
            out[i] += amp * math.exp(-decay * t) * math.sin(phase)

    # 击槌噪声。固定种子 → 每次生成结果字节一致，可入库比对。
    rng = random.Random(seed)
    noise = recipe["noise"]
    noise_t = recipe["noise_t"]
    for i in range(n):
        out[i] += noise * math.exp(-(i / SR) / noise_t) * (rng.random() * 2.0 - 1.0)

    # 起音 / 收尾斜坡、tanh 软限幅 + 归一化（与 deal 共用同一条出口）
    return finalize(out)


# ==================== 发牌音（0.1.35 新增）====================
# 「塑料卡片」的清脆声，一次发牌 = 每张牌一个 55ms 的「嚓」。
# 第一版栽在哪儿（玩测反馈原话：「像敲铁桶」）：我给了 165Hz 的低频「体感」，
#   再叠上 tanh 软限幅，低频被削出谐波、听着就是个桶。塑料片根本不那么响低频。
# 现在三层全在高频，没有任何低频正弦：
#   ① 边缘刮过牌堆的脆点：2.8ms 的亮噪声，高通 3kHz
#   ② 片体（主音）：带通噪声，中心频率 6.8k→2.6kHz 往下扫，Q=1.2，衰减 τ=11ms
#   ③ 顶部细屑：更高一条带通 9k→5kHz，Q=2.0，τ=5ms —— 让「脆」有颗粒感
# 总时长压到 55ms（原来是 85ms），比 60ms 的发牌间隔还短，所以是一记一记的
# 「嚓·嚓·嚓」，不会糊成一片。
# 落桌那一声不在这里：牌飞 0.36s 才到手，落点由调用方复用现成的 land.wav
# （见 main.gd 的 _finish_card_deal）。
DEAL_DUR = 0.055
DEAL_SEED = 20261013


def _onepole(x, cut_fn):
    """一阶低通，截止频率随时间变（cut_fn 收秒、给 Hz）。"""
    out = [0.0] * len(x)
    prev = 0.0
    for i, v in enumerate(x):
        fc = cut_fn(i / SR)
        a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
        prev += a * (v - prev)
        out[i] = prev
    return out


def _highpass(x, fc):
    lp = _onepole(x, lambda _t: fc)
    return [v - l for v, l in zip(x, lp)]


def _bandpass(x, center_fn, q):
    """RBJ 双二阶带通，中心频率随时间变。脆响的「音高」就来自这条共振峰。"""
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        w0 = 2.0 * math.pi * center_fn(i / SR) / SR
        alpha = math.sin(w0) / (2.0 * q)
        a0 = 1.0 + alpha
        b0 = alpha / a0
        b2 = -alpha / a0
        a1 = (-2.0 * math.cos(w0)) / a0
        a2 = (1.0 - alpha) / a0
        y = b0 * v + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, v
        y2, y1 = y1, y
        out[i] = y
    return out


def finalize(out):
    """起音/收尾斜坡 + tanh 软限幅 + 归一化。ding/land/deal 共用同一条出口。"""
    n = len(out)
    na = max(1, int(SR * ATTACK))
    nf = max(1, int(SR * FADE))
    for i in range(na):
        out[i] *= i / na
    for i in range(nf):
        out[n - 1 - i] *= i / nf
    peak = max(abs(v) for v in out) or 1.0
    g = PEAK / peak
    return [math.tanh(v * g * 1.15) / math.tanh(1.15) for v in out]


def synth_deal(seed=DEAL_SEED):
    n = int(SR * DEAL_DUR)
    rng = random.Random(seed)
    white = [rng.random() * 2.0 - 1.0 for _ in range(n)]

    # ① 边缘脆点：极短、极亮
    tick = _highpass([white[i] * math.exp(-(i / SR) / 0.0028) for i in range(n)], 3000.0)
    # ② 片体：中心频率往下扫的带通，是「嚓」的主音
    body = _bandpass(white, lambda t: 2600.0 + 4200.0 * math.exp(-t / 0.012), 1.2)
    body = [body[i] * (1.0 - math.exp(-(i / SR) / 0.0012)) * math.exp(-(i / SR) / 0.011)
            for i in range(n)]
    # ③ 顶部细屑：让高频有颗粒，别听着像一坨白噪
    dust = _bandpass(white, lambda t: 4000.0 + 5000.0 * math.exp(-t / 0.020), 2.0)
    dust = [dust[i] * math.exp(-(i / SR) / 0.005) for i in range(n)]

    return finalize([0.85 * tick[i] + 1.0 * body[i] + 0.45 * dust[i] for i in range(n)])


def write_wav(path, samples):
    """写出 16bit / 单声道 / 44.1kHz 的 WAV。"""
    pcm = array.array("h")
    for v in samples:
        s = int(round(v * 32767.0))
        pcm.append(max(-32768, min(32767, s)))
    if sys.byteorder != "little":
        pcm.byteswap()          # WAV 要求小端
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return len(pcm)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)

    for name, recipe in RECIPES.items():
        frames = write_wav(os.path.join(out_dir, name + ".wav"), synth(recipe))
        print("wrote %s.wav  (%d frames, %.2fs)" % (name, frames, frames / SR))

    frames = write_wav(os.path.join(out_dir, "deal.wav"), synth_deal())
    print("wrote deal.wav  (%d frames, %.2fs)" % (frames, frames / SR))

    print("\n下一步：在 Godot 编辑器里打开一次工程，生成 .import 文件。")


if __name__ == "__main__":
    main()

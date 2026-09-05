extends RefCounted

# 程序化音源：全部PCM由代码合成，无外部音频资产（许可见 assets/LICENSES.md）。
const RATE: float = 22050.0


static func stream(samples: PackedByteArray) -> AudioStreamWAV:
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = int(RATE)
	result.stereo = false
	result.data = samples
	return result


static func ambient_stream() -> AudioStreamWAV:
	var result: AudioStreamWAV = stream(ambient())
	result.loop_mode = AudioStreamWAV.LOOP_FORWARD
	result.loop_begin = 0
	result.loop_end = result.data.size() / 2
	return result


# 生长：上扫拨弦，明亮短促。
static func grow() -> PackedByteArray:
	return _synthesize(0.2, func(t: float, phase: float) -> float:
		var freq: float = lerpf(280.0, 560.0, phase)
		var env: float = _envelope(t, 0.2, 0.008, 3.0)
		return (sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.0 * t)) * env * 0.6)


# 长叶：更亮的叮声加细碎高频。
static func leaf() -> PackedByteArray:
	var rng: Array = [97]
	return _synthesize(0.22, func(t: float, phase: float) -> float:
		var freq: float = lerpf(880.0, 1320.0, phase)
		var env: float = _envelope(t, 0.22, 0.005, 4.0)
		var sparkle: float = _noise(rng) * 0.12 * exp(-t * 30.0)
		return (sin(TAU * freq * t) * 0.55 + sparkle) * env)


# 修剪：短噪声剪切。
static func prune() -> PackedByteArray:
	var rng: Array = [31]
	var smoothed: Array = [0.0]
	return _synthesize(0.14, func(t: float, phase: float) -> float:
		var raw: float = _noise(rng)
		smoothed[0] = smoothed[0] * 0.55 + raw * 0.45
		return smoothed[0] * _envelope(t, 0.14, 0.003, 5.0) * 0.8)


# 断裂/枯死：低频砰加噪声碎裂。
static func snap() -> PackedByteArray:
	var rng: Array = [53]
	return _synthesize(0.3, func(t: float, phase: float) -> float:
		var thump: float = sin(TAU * 88.0 * t) * exp(-t * 14.0)
		var burst: float = _noise(rng) * exp(-t * 22.0) * 0.35
		return (thump * 0.55 + burst) * _envelope(t, 0.3, 0.002, 2.0))


# 接水：双滴答加低频涌动。
static func water() -> PackedByteArray:
	return _synthesize(0.35, func(t: float, phase: float) -> float:
		var drop1: float = sin(TAU * 620.0 * t) * exp(-t * 20.0)
		var drop2: float = sin(TAU * 470.0 * (t - 0.12)) * exp(-(t - 0.12) * 18.0) if t > 0.12 else 0.0
		var swell: float = sin(TAU * 150.0 * t) * exp(-t * 6.0) * 0.3
		return (drop1 * 0.5 + drop2 * 0.5 + swell) * _envelope(t, 0.35, 0.004, 2.0))


# 退守：柔和下行。
static func rescue() -> PackedByteArray:
	return _synthesize(0.5, func(t: float, phase: float) -> float:
		var freq: float = lerpf(400.0, 190.0, phase)
		return sin(TAU * freq * t) * _envelope(t, 0.5, 0.02, 2.5) * 0.5)


# 通关：三音上行。
static func victory() -> PackedByteArray:
	return _synthesize(0.9, func(t: float, phase: float) -> float:
		var sample: float = 0.0
		var notes: Array = [523.25, 659.25, 783.99]
		for index in range(3):
			var start: float = index * 0.28
			if t >= start:
				var local: float = t - start
				sample += sin(TAU * notes[index] * local) * exp(-local * 5.0) * 0.4
		return sample * _envelope(t, 0.9, 0.01, 1.2))


# 环境：低频滤波噪声加慢呼吸调制，8秒无缝循环。
static func ambient() -> PackedByteArray:
	var rng: Array = [7]
	var smoothed: Array = [0.0]
	var seconds: float = 8.0
	return _synthesize(seconds, func(t: float, phase: float) -> float:
		var raw: float = _noise(rng)
		smoothed[0] = smoothed[0] * 0.985 + raw * 0.015
		var breath: float = 0.6 + 0.4 * sin(TAU * t / seconds)
		var hum: float = sin(TAU * 55.0 * t) * 0.05
		return (smoothed[0] * 3.2 * breath + hum) * 0.5)


static func _envelope(t: float, duration: float, attack: float, decay_power: float) -> float:
	if t < attack:
		return t / attack
	return pow(maxf(0.0, 1.0 - (t - attack) / (duration - attack)), decay_power)


static func _noise(state: Array) -> float:
	state[0] = (state[0] * 48271) % 2147483647
	return float(state[0]) / 1073741823.5 - 1.0


static func _synthesize(seconds: float, wave: Callable) -> PackedByteArray:
	var frames: int = int(seconds * RATE)
	var data: PackedByteArray = PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t: float = float(i) / RATE
		var sample: float = clampf(wave.call(t, float(i) / frames), -1.0, 1.0)
		var value: int = int(sample * 32767.0)
		if value < 0:
			value += 65536
		data[i * 2] = value & 0xFF
		data[i * 2 + 1] = (value >> 8) & 0xFF
	return data

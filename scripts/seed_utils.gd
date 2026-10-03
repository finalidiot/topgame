extends RefCounted
class_name SeedUtils

## Versioned FNV-1a over UTF-8, rather than engine hash() or shared RNG state.
## All multiplication fits in signed 64 bits before the explicit 32-bit mask.
## Keep this derivation stable: recorded run seeds depend on its output.
static func derive(base_seed: int, domain: String) -> int:
	var value: int = 2166136261
	var bytes: PackedByteArray = ("topgame-seed-v1|%d|%s" % [base_seed, domain]).to_utf8_buffer()
	for byte: int in bytes:
		value = ((value ^ byte) * 16777619) & 0xffffffff
	return value

class_name WorldState
extends RefCounted
## Global world state, shared through static members.
##
## Holds the one world seed everything derived from the integer hash follows:
##     WorldState.seed                        # read the current seed
##     WorldState.seed = 42                   # change it (clamped to uint32)
##     WorldState.randomize_seed()            # pick a random one
##     WorldState.seed_changed.connect(f)     # f(seed: int) after each change
##
## Static members instead of an autoload, so the class resolves everywhere,
## including in `--check-only` and `--script` runs where autoloads do not exist.

const MAX_SEED := 0xFFFFFFFF
## Seed 1 matches the reference renders.
const DEFAULT_SEED := 1

## Emitted with the new seed after it changed to a different value.
static var seed_changed: Signal:
	get:
		return _emitter.seed_changed

static var seed: int = DEFAULT_SEED:
	set = set_seed

static var _emitter := _Emitter.new()


class _Emitter:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal seed_changed(seed: int)


static func set_seed(value: int) -> void:
	var clamped := clampi(value, 0, MAX_SEED)
	if clamped == seed:
		return
	seed = clamped
	_emitter.seed_changed.emit(seed)


## Picks a uniformly random seed and applies it.
static func randomize_seed() -> void:
	set_seed(randi() & MAX_SEED)

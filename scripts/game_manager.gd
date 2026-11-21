extends Node

## Состояние забега. Autoload, поэтому доступен всем игровым системам.
##
## Генератор остаётся детерминированным: GameManager хранит только seed,
## номер этажа, время забега и награды, но не влияет на выбор комнат.
## Ключи и сложность живут весь забег и не сбрасываются на новом этаже.

signal gold_changed(total: int)
signal floor_changed(floor_index: int)
signal keys_changed(count: int)
signal message_shown(text: String)
signal run_time_changed(elapsed: float)
signal difficulty_changed(value: float)

const START_GOLD: int = 0
const DIFFICULTY_PER_MINUTE: float = 0.2
const COIN_BONUS_PER_DIFFICULTY: float = 0.25
const PRICE_GROWTH_PER_DIFFICULTY: float = 0.20

# Состояние игры
var player_health: int = 100
var player_max_health: int = 100
var current_floor: int = 1
var run_seed: int = 0
var gold: int = START_GOLD
var keys: int = 0

## Время/сложность забега. Таймер считает только во время активной игры.
var run_time: float = 0.0
var difficulty: float = 0.0
var run_active: bool = false

func _ready() -> void:
	print("=== GAME MANAGER READY ===")

func _process(delta: float) -> void:
	if not run_active:
		return
	set_run_time(run_time + maxf(0.0, delta))

func reset_run(seed_value: int) -> void:
	run_seed = int(seed_value)
	current_floor = 1
	gold = START_GOLD
	keys = 0
	run_time = 0.0
	difficulty = 0.0
	run_active = true
	floor_changed.emit(current_floor)
	gold_changed.emit(gold)
	keys_changed.emit(keys)
	run_time_changed.emit(run_time)
	difficulty_changed.emit(difficulty)

func stop_run_timer() -> void:
	run_active = false

func set_floor(value: int) -> void:
	current_floor = maxi(1, int(value))
	floor_changed.emit(current_floor)

func set_run_time(seconds: float) -> void:
	run_time = maxf(0.0, float(seconds))
	var next_difficulty := run_time / 60.0 * DIFFICULTY_PER_MINUTE
	if not is_equal_approx(next_difficulty, difficulty):
		difficulty = next_difficulty
		difficulty_changed.emit(difficulty)
	run_time_changed.emit(run_time)

static func format_time(seconds: float) -> String:
	var total_ms := int(round(maxf(0.0, seconds) * 1000.0))
	var minutes := total_ms / 60000
	var seconds_part := (total_ms / 1000) % 60
	var milliseconds := total_ms % 1000
	return "%d:%02d:%03d" % [minutes, seconds_part, milliseconds]

func get_difficulty() -> float:
	return difficulty

# ============================================
# МОНЕТЫ И ЦЕНЫ
# ============================================
func coin_multiplier() -> float:
	return 1.0 + COIN_BONUS_PER_DIFFICULTY * difficulty

func price_multiplier() -> float:
	return 1.0 + PRICE_GROWTH_PER_DIFFICULTY * difficulty

func scale_coins(base_amount: int) -> int:
	if base_amount <= 0:
		return 0
	return maxi(1, int(round(float(base_amount) * coin_multiplier())))

func scaled_price(base_price: int) -> int:
	if base_price <= 0:
		return 0
	return maxi(1, int(round(float(base_price) * price_multiplier())))

## Единая точка получения монет: все источники проходят через неё.
func grant_coins(base_amount: int) -> int:
	var amount := scale_coins(base_amount)
	if amount > 0:
		add_gold(amount)
	return amount

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

# ============================================
# КЛЮЧИ (сохраняются между этажами)
# ============================================
func get_key_count() -> int:
	return keys

func add_key(amount: int = 1) -> void:
	if amount <= 0:
		return
	keys += amount
	keys_changed.emit(keys)

func spend_key(amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if keys < amount:
		return false
	keys -= amount
	keys_changed.emit(keys)
	return true

func show_message(text: String) -> void:
	if text == "":
		return
	print("[MESSAGE] ", text)
	message_shown.emit(text)

## Совместимость: HUD теперь читает ключи из GameManager.
func notify_keys_changed() -> void:
	keys_changed.emit(keys)

# ============================================
# СЛУЧАЙНЫЕ НАГРАДЫ
# ============================================
## Порог 1% и выбор ключ/сундук разведены, чтобы тесты могли задавать
## детерминированные значения. В игре параметры остаются пустыми.
func roll_enemy_kill_reward(roll: float = -1.0, kind_roll: float = -1.0) -> String:
	var chance := roll if roll >= 0.0 else randf()
	if chance >= 0.01:
		return ""
	var pick := kind_roll if kind_roll >= 0.0 else randf()
	return "key" if pick < 0.5 else "chest"

func roll_room_clear_reward(roll: float = -1.0) -> String:
	var chance := roll if roll >= 0.0 else randf()
	if chance < 0.10:
		return "chest"
	if chance < 0.50:
		return "coins"
	if chance < 0.75:
		return "key"
	return "nothing"

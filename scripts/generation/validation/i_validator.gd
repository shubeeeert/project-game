extends RefCounted

## Контракт валидатора. Валидатор только читает данные и возвращает список проблем.

func id() -> String:
	return "base"

func validate(_floor_data: Dictionary, _config: Dictionary) -> Array:
	return []

func enabled(_config: Dictionary) -> bool:
	return true

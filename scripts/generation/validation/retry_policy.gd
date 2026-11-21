extends RefCounted

## Политика повторов генерации. Детерминирована: номер попытки участвует
## в имени RNG-потока, поэтому повтор даёт другой, но воспроизводимый этаж.

static func max_attempts(config: Dictionary) -> int:
	return maxi(1, int(config.get("max_attempts", 3)))

static func stream_name(attempt_index: int) -> String:
	return "attempt:%d" % attempt_index

static func should_retry(attempt_index: int, attempts: int, report: RefCounted) -> bool:
	if report == null:
		return true
	return report.has_blocking() and attempt_index + 1 < attempts

static func requires_regeneration(floor_data: Dictionary) -> bool:
	return bool(floor_data.get("metadata", {}).get("needs_regeneration", false))

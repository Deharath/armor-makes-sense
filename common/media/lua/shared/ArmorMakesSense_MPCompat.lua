ArmorMakesSense = ArmorMakesSense or {}

ArmorMakesSense.MP = ArmorMakesSense.MP or {}
local MP = ArmorMakesSense.MP

MP.NET_MODULE = "ArmorMakesSenseRuntime"
MP.HARNESS_PING_COMMAND = "harness_ping"
MP.DIAG_COMMAND = "diag"
MP.REQUEST_SNAPSHOT_COMMAND = "request_snapshot"
MP.SNAPSHOT_COMMAND = "snapshot"
MP.DIAG_DUMP_REQUEST_COMMAND = "diag_dump_request"
MP.DIAG_DUMP_COMMAND = "diag_dump"
MP.SNAPSHOT_FALLBACK_SECONDS = 2
MP.MOD_STATE_KEY = "ArmorMakesSenseState"
MP.SCRIPT_VERSION = "1.1.7"
MP.SCRIPT_BUILD = "ams-b42-2026-03-08-v117"

return MP

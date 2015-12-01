local sysmem = ngx.shared.sysmem;
local packet_len = 131072

sysmem:set('debug',0)

sysmem:set('keys_count', 0)
sysmem:set('worker_id', 0)


sysmem:set('new_start', 0)
sysmem:set('packet_len', packet_len)
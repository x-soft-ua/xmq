--
--Модуль статус-строчки, XMQ 2.0RC
--  09.12.2014
--
--идентификатор воркера

--разделяемая память
local sysmem = ngx.shared.sysmem;

--получаем GET аргументы
local args = ngx.req.get_uri_args()

--подключаемся к БД
    local redis = require "lib.redis"
    local red = redis:new()
    red:set_timeout(100)
    local ok, err = red:connect("unix:/tmp/redis_xmq.sock")
    if (not ok) then
        ngx.say('{"error":"redis_error"}')
        return
    end

--функции
function urlencode(str)
   if (str) then
      str = string.gsub (str, "\n", "\r\n")
      str = string.gsub (str, "([^%w ])",
         function (c) return string.format ("%%%02X", string.byte(c)) end)
      str = string.gsub (str, " ", "+")
   end
   return str    
end

function urldecode(str)
    local hex_to_char = function(x)
        return string.char(tonumber(x, 16))
    end

    local unescape = function(url)
        return url:gsub("%%(%x%x)", hex_to_char)
    end
end
--/функции




--выводим состояние по ключам в БД

if(args['key']=='all') then
    worker_id = sysmem:get('worker_id')
    ngx.say('max_worker_id='..worker_id)
    keys = red:keys('d_*')
    ngx.say(ngx.now())
    ngx.say('{')
    for _i, _val in pairs(keys) do
        if(_i>1) then ngx.say(',"key":"'.._val..'"') else
        ngx.say('"key":"'.._val..'"') end
    end
    ngx.say('}')
elseif(args['key']=='flushall') then
    ok, err = red:flushall()
    if(not err) then
        ngx.say('{"status":"flushall_ok"}')
    else
        ngx.say('{"error":"redis_error"}')
    end
elseif(args['debug']=='1') then
    sysmem:set('debug',1)
    ngx.say('{"status":"debug_on"}')
elseif(args['debug']=='0') then
    sysmem:set('debug',0)
    ngx.say('{"status":"debug_off"}')
--elseif(args['key']) then
--    if(args['history']) then
--        message = history:get(urlencode(args['key']))
--        if(args['data']) then
--            data = history:get(urlencode(args['key'])..'data')
--        end
--    else
--        message = ebuf:get(urlencode(args['key']))
--    end
--    if(not message) then message = 'null' end
--    ngx.say('{"message":"'..message..'"}')
--    if(data) then
--        ngx.say('{"data":"'..data..'"}')
--    end
else
    ngx.say('{"message":"null"}')
end


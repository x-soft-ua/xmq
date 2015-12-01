--
--Модуль добавления сообщений, XMQ 2.0RC
--  09.12.2014
--
--идентификатор воркера
wpid = ngx.worker.pid()

--инициализируем общую разделяемую память
sysmem = ngx.shared.sysmem;

--разделяемая память для воркера
    --ebuf = ngx.shared['work'..worker_id]

--номер воркера (от 1 до 12)
    worker_id = sysmem:get('w'..wpid)

--подключаемся к БД
    local redis = require "lib.redis"
    local red = redis:new()
    --red:set_timeout(50)
    local ok, err = red:connect("unix:/tmp/redis_xmq.sock")
    if (not ok) then
        ngx.say('{"error":"redis_error"}')
        return
    end

--размер HTTP пакета
    packet_len = sysmem:get('packet_len')


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
    
    function parse_key(t)
                local ret = {}
                local k = 1
                t = t:gsub("::", "|")
                for val in string.gmatch(t, "([^|]+)") do
                    ret[k]=val
                    k = k + 1
                end
                return ret
    end
--/функции

--получаем GET аргументы и ставим TTL для HTTP пакета
    local args = ngx.req.get_uri_args()
    local savettl = 10

--проверяем обязательные GET аргументы
    if(not args['uri'] or not args['host'] or not args['port']) then
        ngx.say('{"error":"dst_not_declared"}')
        return
    end

--модуль истории HTTP пакетов
    --local history = 0
    --if(args['history']) then history = 1 end

--модуль QOS (для важных сообщений - увеличиваем время хранения в памяти)
    local qos = 0
    if(args['qos']) then 
        qos = 1 
        savettl = 7200
    end

--читаем входящее сообщение
    local reqsock, err = ngx.req.socket()
    local message = ''
    if(not err) then
        --local line, err, partial = reqsock:receive()
        local reader = reqsock:receiveuntil("\r\n")
        local data, err, partial = reader()
        --if not line then
        --    return
        --end
        message = urlencode(data)
    else
        ngx.say('{"error":"'..err..'"}')
    end

--получаем время 
    local socket = require "socket"
    local nowtime = socket.gettime()
--генерируем уникальный ID сообщения
    --req_id = math.random(1000,9999)..nowtime
    --req_time = nowtime

--получаем длину сообщения
    local message_len = message:len()

--сообщение обязано быть текстом, иначе труба :)
    if(type(message)=='string') then
        --получаем номер пакета
        packet_index = tonumber(red:get('pi_'..worker_id))
        if(not packet_index or type(packet_index)~='number') then
            --номер пакета начинается с "0"
            packet_index = 0
            red:set('pi_'..worker_id, packet_index)
            red:expire('pi_'..worker_id, 3600)
        end
        
        --ключ HTTP пакета
        data_key = 'd_'..packet_index..'_'..worker_id..'::'..qos..'::'..args['host']..'::'..args['port']..'::'..args['uri']
        
        --добавляем ключик к списку
        red:sadd('k_'..worker_id, data_key)
        
        --добавляем разделитель между сообщениями
        message = '::'..message
        
        --сохраняем и устанавливем TTL
        total_len, err = red:append(data_key, message)
        red:expire(data_key, savettl)
        
        --если ошибка, кричим в еррор-лог!
        if(err) then
            ngx.log(ngx.ERR, 'APPEND_ERROR')
        end
        
        --проверяем длину, если выползаем за предел, сдвигаем номер пакета
        total_len = tonumber(total_len)
        if(total_len > packet_len) then
            red:incrby('pi_'..worker_id,1)
        end
        
        --ngx.log(ngx.ERR, 'LEN'..total_len)
        
        --если с длиной все ок, говорим что все ОК :-)
        if(type(total_len)=='number') then
            ngx.say('{"add":"ok","len":"'..message_len..'","datakey":"'..data_key..'"}')
        end
    end
    
    red:set_keepalive(1000, 10)

--Вродь как все
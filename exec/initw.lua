--
--Модуль воркера, XMQ 2.0RC
--  09.12.2014
--
--идентификатор воркера


--идентификатор воркера
wpid = ngx.worker.pid()

--инициализируем общую разделяемую память
local sysmem = ngx.shared.sysmem;

--раздаем воркерам свой уникальный ID (от 1 до 12, при 12 потоках)
workers_id = sysmem:incr('worker_id',1)
sysmem:set('w'..wpid, workers_id)

--интервал для воркеров (в секундах)
local delay = 1



--функции
--local clock = os.clock
function sleep(n)
    sock = require "socket"
    sock.sleep(n)
    
--  local t0 = clock()
--  while clock() - t0 <= n do end
end

function st(t)
            local ret = table.concat(t,",")
            return ret
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

function explode(patt, t)
    if(type(patt)~='string') then
        return nil
    end
    local ret = {}
    local k = 1
    t = t:gsub(patt, "|")
    for val in string.gmatch(t, "([^|]+)") do
        ret[k]=val
        k = k + 1
    end
    return ret
end


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
    return str:gsub("%%(%x%x)", hex_to_char)
end

function debug_print(msg)
    if(not msg) then
        return 0
    end
    debug = sysmem:get('debug')
    if(debug==0) then
        return 0
    end
    
    ngx.log(ngx.ERR, msg)
    return 1
end

function http_post(host, port, uri, data, msg_id, keep_alive, sock, qos)

    
    if(keep_alive) then
        keep_alive = "Connection: Close\r\n"
    end
    
    if(not data) then
        return 0
    end
    
    if(not msg_id) then
        msg_id = data:len()
    end
    
    checksum_md5 = ngx.md5(data)
    msg_id_md5 = ngx.md5(data)
    
    
    local request = "POST "..uri.." HTTP/1.0\r\n"..
                    "Host: "..host.."\r\n"..
                    "Content-Type: application/x-www-form-urlencoded\r\n"..
                    "Content-Length: "..(data:len()).."\r\n"..keep_alive..
                    "X-xmq-version: 2.0\r\n"..
                    "X-xmq-msg-len: "..data:len().."\r\n"..
                    "X-xmq-msg-id: "..msg_id_md5.."\r\n"..
                    "X-xmq-msg-checksum: "..checksum_md5..
                    "\r\n\r\n"..data.."\r\n"
                    
    local bytes, err = sock:send(request)

    --ngx.log(ngx.ERR, "Bytes send: ", bytes)
    
    local httpdata = ''
    
    if(qos==1) then
        httpdata = ''
        line = sock:receive()
        while(line) do
            httpdata = httpdata..line
            line = sock:receive()
        end
    else
        httpdata = 'ok<data_send_qos_disabled>'
    end

    keep_alive = nil
    checksum = nil
    data = nil
    request = nil
    
    if (not httpdata) then
        return 0
    else
        return httpdata
    end
    
end
--/функции


--погнали
local handler

handler = function  (premature)
    
    
    
    --берем идентификатор воркера
    wpid = ngx.worker.pid()
    --номер воркера (от 1 до 12)
    worker_id = sysmem:get('w'..wpid)
    --инициализируем разделяемую память
    sysmem = ngx.shared.sysmem;

    --идем в БД
    local redis = require "lib.redis"
    local red = redis:new()
    --red:set_timeout(1000)
    local ok, err = red:connect("unix:/tmp/redis_xmq.sock")
    
    --если законетились
    if (ok) then
        --дебаг воркеров
        red:sadd('workers', wpid)
        
        --берем список накопившихся HTTP пакетов для нашего воркера
        --keys = red:keys('d_*_'..wpid..'*')
        keys = red:smembers('k_'..worker_id)
        
--        debug_print("Debug keys["..worker_id.."]:"..table.concat(keys, ','))
        
        --перелистываем
        if(type(keys)=='table') then
            for _i, _val in pairs(keys) do
                --структура:
                --d_0_29304::1::m3.c8.net.ua::90::/xmq_controller.php
                
                --раскладываем ключ на составляющие
                key = explode('::', _val)
                
                --первый элемент раскладываем на составляющие
                moved = explode('_', key[1])
                
                --узнаем кому, и как отправлять :)
                qos = tonumber(key[2])
                host = key[3]
                port = key[4]
                uri = key[5]
                
                if(moved[1]~='m') then
                    --генерируем псевдослучайную приставку
                    local rand_index =  math.random(1000,9999)
                    _val_moved = 'm_'..rand_index..'_'.._val
                    --пихаем все в транзакцию
                    local ok, err = red:multi()
                    red:rename(_val, _val_moved)            --переименовываем
                    red:del(_val)                           --удаляем исходный
                    red:srem('k_'..worker_id, _val)         --удаляем ключ из списка
                    red:sadd('k_'..worker_id, _val_moved)   --добавляем новый в список
                    ans, err = red:exec()
                else
                    _val_moved = _val
                end
                
                --вытягиваем сам HTTP пакет
                message, err = red:get(_val_moved)
                
                
                
                --если все ровно
                if(not err and type(message)=='string') then
                    if(host and port and uri) then
                        
                        --конектимся к получателю
                        sock = ngx.socket.tcp()
                        local ok, err = sock:connect(host, port)
                        
                        if(not err) then
                            --нужен ли QOS (ожидать ответа)
                            if(qos~=1) then qos = 0 end
                            --на всяк-пожарный, берем длину HTTP пакета
                            message_len = message:len()
                            
                            --отсылаем
                            sended = http_post(host, port, uri, message, _val_moved, 0, sock, qos)
                            --закрываем соденинение
                            sock:close()
                            
                            --читаем что нам ответила функция http_post
                            --пытаемся найти хорошие вести
                            response_code = string.match(sended, 'ok<.*>')
                            --если вестей хороших нет
                            if(not response_code) then
                                --ищем плохие вести
                                response_err_code = string.match(sended, 'error<.*>')
                                --если и они утсутствуют, то хз... выводим в error.log HTTP ответ :)
                                if(not response_err_code) then response_err_code = sended--'destination is not reachable'
                                end
                                --собственно само логирование
                                debug_print('[qos'..qos..']XMQ Error[wid:'..worker_id..']['..message_len..']: '..response_err_code)
                            else
                                debug_print('[qos'..qos..']XMQ OK[wid:'.._val_moved..']['..message_len..']: '..response_code)
                                --если же все ровно, давим пакет из редиски
                                ok1, err1 = red:del(_val_moved)
                                ok2, err2 = red:srem('k_'..worker_id, _val_moved)
                                --если призошла ошибка при удалении, скорее всего отвалился коннект по таймауту
                                --пересоединяемся и удаляем
                                if(err1 or err2) then
                                    local red = redis:new()
                                    --red:set_timeout(1000)
                                    local ok, err = red:connect("unix:/tmp/redis_xmq.sock")
                                    red:del(_val_moved)
                                    red:srem('k_'..worker_id, _val_moved)
                                end
                            end
                        end
                    end
                end
                
            end
        end
    end
    
    red:set_keepalive(1000, 10)
    
    --устанавливаем таймер
    local ok, err = ngx.timer.at(delay, handler)
    if not ok then
        debug_print("Timer Slave: "..err)
        --херня с таймером?...
        return
    end

end


local ok, err = ngx.timer.at(delay, handler)

if not ok then
    --ngx.log(ngx.ERR, "Timer Main: ", err)
    return
end




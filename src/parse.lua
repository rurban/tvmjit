
local char = string.char
local error = error
local _find = string.find
local format = string.format
local op = tvm.op.new
local quote = tvm.quote
local setmetatable= setmetatable
local sub = string.sub
local tconcat = table.concat
local tonumber = tonumber
local wchar = tvm.wchar
local io = require 'io'

local function find (s, patt)
    return patt ~= '' and _find(s, patt, 1, true)
end

local digit = '0123456789'
local sign = '+-'
local digit_sign = digit .. sign
local xdigit = 'ABCDEF'
            .. 'abcdef' .. digit
local newline = '\n\r'
local space = ' \f\t\v'
local not_name = '():' .. space .. newline

local P = {}

function P:_resetbuffer ()
    self.buff = {}
end

function P:_next ()
    self.pos = self.pos + 1
    self.current = sub(self.z, self.pos, self.pos)
    return self.current
end

function P:_save_and_next ()
    self:_save(self.current)
    self:_next()
end

function P:_save (c)
    self.buff[#self.buff+1] = c
end

function P:_txtToken (token)
    if     token == '<name>'
        or token == '<string>'
        or token == '<number>' then
        return tconcat(self.buff)
    elseif token == '' then
        return '<eof>'
    else
        return token
    end
end

local function chunkid (source, max)
    local first = sub(source, 1, 1)
    if     first == '=' then    -- 'literal' source
        return sub(source, 2, 1 + max)
    elseif first == '@' then    -- file name
        if #source <= max then
            return sub(source, 2)
        else
            return '...' .. sub(source, -max)
        end
    else                        -- string; format as [string "source"]
        source = sub(source, 1, (find(source, "\n") or #source) - 1)
        source = (#source < (max - 11)) and source or sub(source, 1, max - 14) .. '...'
        return '[string "' .. source .. '"]'
    end
end

function P:_lexerror (msg, token)
    msg = format("%s:%d: %s", chunkid(self.source, 60), self.linenumber, msg)
    if token then
        msg = format("%s near %s", msg, self:_txtToken(token))
    end
    error(msg)
end

function P:syntaxerror(msg)
    self:_lexerror(msg, self.token)
end

function P:_inclinenumber ()
    local old = self.current
    self:_next()
    if find(newline, self.current) and self.current ~= old then
        self:_next()
    end
    self.linenumber = self.linenumber + 1
end

function P:setinput(z, source)
    self.z = z
    self.linenumber = 1
    self.lastline = 1
    self.source = source
    self.buff = {}
    self.pos = 0
    self:_next()
end

function P:_check_next (set)
    if not find(set, self.current) then
        return false
    end
    self:_save_and_next()
    return true
end

function P:_read_numeral ()
    if find(sign, self.current) then
        self:_save_and_next()
    end
    local expo = 'Ee'
    local first = self.current
    self:_save_and_next()
    if first == '0' and self:_check_next('Xx') then
        expo = 'Pp'
    end
    while true do
        if self:_check_next(expo) then
            self:_check_next('+-')
        elseif find(xdigit, self.current) or self.current == '.' then
            self:_save_and_next()
        else
            break
        end
    end
    local val = tonumber(tconcat(self.buff))
    if not val then
        self:_lexerror("malformed number", '<number>')
    end
    self.seminfo = val
    self.token = '<number>'
end

function P:_escerror (c, msg)
    self:_resetbuffer()
    self:_save(c)
    self:_lexerror(msg, '<string>')
end

function P:_readhexaesc ()
    local r = ''
    for i = 1, 2 do
        local c = self:_next()
        r = r .. c
        if not find(xdigit, c) then
            self:_escerror('x' .. r, "hexadecimal digit expected")
        end
    end
    return char(tonumber(r, 16))
end

function P:_readuniesc ()
    local r = ''
    for i = 1, 4 do
        local c = self:_next()
        r = r .. c
        if not find(xdigit, c) then
            self:_escerror('x' .. r, "hexadecimal digit expected")
        end
    end
    return wchar(tonumber(r, 16))
end

function P:_read_string ()
    self:_save_and_next()
    while self.current ~= '"' do
        if     self.current == '' then
            self:_lexerror("unfinished string", '')
        elseif self.current == '\\' then
            self:_next()
            if     self.current == 'a' then
                self:_next()
                self:_save('\a')
            elseif self.current == 'b' then
                self:_next()
                self:_save('\b')
            elseif self.current == 'f' then
                self:_next()
                self:_save('\f')
            elseif self.current == 'n' then
                self:_next()
                self:_save('\n')
            elseif self.current == 'r' then
                self:_next()
                self:_save('\r')
            elseif self.current == 't' then
                self:_next()
                self:_save('\t')
            elseif self.current == 'v' then
                self:_next()
                self:_save('\v')
            elseif self.current == 'x' then
                local c = self:_readhexaesc()
                self:_next()
                self:_save(c)
            elseif self.current == 'u' then
                local c = self:_readuniesc()
                self:_next()
                self:_save(c)
            elseif self.current == '\n'
                or self.current == '\r' then
                self:_inclinenumber()
                self:_save('\n')
            elseif self.current == '\\' then
                self:_next()
                self:_save('\\')
            elseif self.current == '"' then
                self:_next()
                self:_save('"')
            elseif self.current == '\'' then
                self:_next()
                self:_save('\'')
            elseif self.current == '' then
                -- will raise an error next loop
            else
                self:_escerror(self.current, "invalid escape sequence")
            end
        elseif self.current == '\n'
            or self.current == '\r' then
            self:_inclinenumber()
            self:_save('\n')
        else
            self:_save_and_next()
        end
    end
    self:_save_and_next()
    self.seminfo = sub(tconcat(self.buff), 2, -2)
    self.token = '<string>'
    return
end

function P:_read_name ()
    while true do
        if find(not_name, self.current) then
            break
        elseif self.current == '\\' then
            self:_next()
            self:_save_and_next()
        else
            self:_save_and_next()
        end
    end
    self.seminfo = tconcat(self.buff)
    self.token = '<name>'
    return
end

function P:next ()
    self.lastline = self.linenumber
    self:_resetbuffer()
    while true do
        if     find(newline, self.current) then
            self:_inclinenumber()
        elseif find(space, self.current) then
            self:_next()
         elseif self.current == ';' then
             self:_next()
             while not find(newline, self.current) and self.current ~= '' do
                self:_next()
             end
        elseif self.current == '(' then
            self:_next()
            self.token = '('
            return
        elseif self.current == ')' then
            self:_next()
            self.token = ')'
            return
        elseif self.current == ':' then
            self:_next()
            self.token = ':'
            return
        elseif self.current == '"' then
            return self:_read_string()
        elseif find(digit_sign, self.current) then
            return self:_read_numeral()
        elseif self.current == '' then
            self.token = ''
            return
        else
            return self:_read_name()
        end
    end
end

function P:BOM ()
    -- UTF-8 BOM
    if self.current == char(0xEF) then
        self:_next()
        if self.current == char(0xBB) then
            self:_next()
            if self.current == char(0xBF) then
                self:_next()
            end
        end
    end
end

function P:shebang ()
    self:BOM()
    if self.current == '#' then
        while self.current ~= '\n' do
            self:_next()
        end
        self:_inclinenumber()
    end
end

function P:expr ()
    local token = self.token
    if     token == '(' then
        return self:table()
    elseif token == '<string>' then
        local v = self.seminfo
        self:next()
        return quote(v)
    elseif token == '<number>'
        or token == '<name>' then
        local v = self.seminfo
        self:next()
        return v
    else
        self:syntaxerror("<expr> expected")
    end
end

function P:table ()
    self:next()
    local t = op{}
    while self.token ~= ')' do
        local v = self:expr()
        if self.token == ':' then
            self:next()
            t:addkv(v, self:expr())
        else
            t:push(v)
        end
    end
    self:next()
    return t
end

local function parse (s, chunkname)
    local p = setmetatable({}, { __index=P })
    p:setinput(s, chunkname or s)
    p:BOM()
    p:shebang()
    local t = op{'!do'}
    p:next()
    while p.token == '(' do
        t:push(p:table())
    end
    if p.token ~= '' then
        p:syntaxerror("<eof> expected")
    end
    return #t == 2 and t[2] or t
end
tvm.parse = parse

function tvm.parsefile (fname)
    local chunk
    if fname then
        local fh = assert(io.open(fname, 'r'))
        chunk = fh:read'*a'
        fh:close()
    else
        chunk = io.stdin:read'*a'
        fname = '=stdin'
    end
    return parse(chunk, fname)
end


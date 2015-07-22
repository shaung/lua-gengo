-- @module gengo

local cjson = require 'cjson'
local httpclient = require 'httpclient'
local sha1 = require 'sha1'
local pp = require 'pl.pretty'

local _Gengo = {}
local Gengo = {}

_Gengo.VERSION = "0.0.1"

local function merge_defaults(t1, defaults)
  for k, v in pairs(defaults) do
    if not t1[k] then t1[k] = v end
  end
  return t1
end

----------------------------------------------------------------------------
-- URL-encode a string (see RFC 2396)
----------------------------------------------------------------------------
function escape (str)
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "([^0-9a-zA-Z ])", -- locale independent
        function (c) return string.format ("%%%02X", string.byte(c)) end)
    str = string.gsub (str, " ", "+")
    return str
end

local function map(t, func)
  local res = {}
  for k, v in pairs(t) do
    table.insert(res, func(k, v))
  end
  return res
end

local function build_kws(t)
  local f = function(k, v)
    if type(v) == "table" then
        v = cjson.encode(v)
    end
    return k..'='..escape(v)
  end
  return table.concat(map(t, f), '&')
end

local function hexdigest(buf)
    local hexdigest = ""
    for i=1, #buf do
        hexdigest = hexdigest .. string.format("%02x", string.byte(buf:sub(i, i)))
    end
    return hexdigest
end

local defaults = {
  api_base_url           = "https://api.gengo.com/v2",
  api_sandbox_base_url   = "https://api.sandbox.gengo.com/v2"
}

function Gengo.new(params)
  local self = {}
  local args = params or {}

  self.public_key = nil
  self.private_key = nil

  if args.public_key then
    self.public_key = args.public_key
  else
    error('public key needed')
  end

  if args.private_key then
    self.private_key = args.private_key
  else
    error('private key needed')
  end

  pp.dump(args)
  self.sandbox = args.sandbox or false
  self.debug = args.debug or false

  self.client = httpclient.new()

  self.user_agent = args.user_agent or "gengo-lua ".._Gengo.VERSION
  setmetatable(self, {__index = _Gengo})
  return self
end

function _Gengo:account()
  local _self = self
  base_endpoint = '/account'
  return {
    stats = function()
        return _self:make_request(base_endpoint..'/stats/', "get", {})
    end,
    balance = function()
        return _self:make_request(base_endpoint..'/balance/', "get", {})
    end,
    preferred_translators = function()
        return _self:make_request(base_endpoint..'/preferred_translators/', "get", {})
    end
  }
end

function _Gengo:translate()
  local _self = self
  base_endpoint = '/translate'
  return {
    jobs = {
            list = function()
                return _self:make_request(base_endpoint..'/jobs', "get")
            end,
            get = function(ids)
                local paras = ''
                if type(ids) == "table" then
                    paras = table.concat(ids, ",")
                else
                    paras = tostring(ids)
                end
                return _self:make_request(base_endpoint..'/jobs'..paras, "get")
            end,
            create = function(data)
                return _self:make_request(base_endpoint..'/jobs', "post", data)
            end,
            update = function(data)
                return _self:make_request(base_endpoint..'/jobs', "put", data)
            end
    },
    job = function(id)
        endpoint = base_endpoint..'/job/'..tostring(id)
        return {
            get = function()
                return _self:make_request(endpoint, "get")
            end,
            create = function(data)
                return _self:make_request(endpoint, "post", data)
            end,
            update = function(data)
                return _self:make_request(endpoint, "put", data)
            end,
            delete = function()
                return _self:make_request(endpoint, "delete")
            end,
            comments = {
                get=function()
                    return _self:make_request(endpoint..'/comments', "get")
                end,
                post=function(data)
                    return _self:make_request(endpoint..'/comments', "post", data)
                end
            },
            feedback = {
                get = function()
                    return _self:make_request(endpoint..'/feedback', "get")
                end
            },
            revisions = {
                get = function(id)
                    return _self:make_request(endpoint..'/revision/'..tostring(id), "get")
                end,
                list = function()
                    return _self:make_request(endpoint..'/revisions', "get")
                end
            }
        }
    end,
    glossary = function(id)
        if id ~= nil then
            endpoint = base_endpoint..'/glossary/'..tostring(id)
            return {
                get=function()
                    return _self:make_request(endpoint, "get")
                end
            }
        else
            endpoint = base_endpoint..'/glossary/'
            return {
                list = function()
                    return _self:make_request(endpoint, "get")
                end
            }
        end
    end,
    order = function(id)
        endpoint = base_endpoint..'/order/'..tostring(id)
        return {
            get=function()
                return _self:make_request(endpoint, "get")
            end,
            delete=function()
                return _self:make_request(endpoint, "delete")
            end,
            comments={
                get=function()
                    return _self:make_request(endpoint..'/comments', "get")
                end,
                set=function(data)
                    return _self:make_request(endpoint..'/comments', "post", data)
                end
            }
        }
    end,
    service = {
        languages = function()
            return _self:make_request(endpoint..'/languages', "get")
        end,
        language_matrix = function()
            return _self:make_request(endpoint..'/language_matrix', "get")
        end,
        language_pairs = function()
            return _self:make_request(endpoint..'/language_pairs', "get")
        end
    }
  }
end

function Set(list)
    local set = {}
    for _, l in ipairs(list) do set[l] = true end
    return set
end

function _Gengo:_build_uri(endpoint)
  local url = ''
  if self.sandbox then
    url = defaults.api_sandbox_base_url..endpoint
  else
    url = defaults.api_base_url..endpoint
  end
  return url
end

function _Gengo:_build_params(opts)
  local params = {}
  params = merge_defaults(params, opts or {})
  params['api_key'] = self.public_key
  params['ts'] = tostring(os.time())
  params['api_sig'] = sha1.hmac(self.private_key, params['ts'])
  return params
end

local _valid_methods = Set{"get", "put", "post", "delete"}

function _Gengo:make_request(endpoint, method, data, opts)
  if self.debug then
    print(endpoint)
    print(method)
    print(data)
    print(opts)
  end
  method = string.lower(method)
  if _valid_methods[method] == nil then return nil end

  local url = self:_build_uri(endpoint)
  local params = self:_build_params(opts)

  if self.debug then
    print(url)
    pp.dump(params)
  end

  headers = { accept = "application/json" }

  local res = ''
  if method == "get" then
    opts = {
        headers=headers,
        params=params
    }
    res = self.client[method](self.client, url, opts)
  else
    if method == "post" then
      data = merge_defaults({data=data}, params)
      local post_data = build_kws(data)
      if self.debug then
        print(post_data)
      end
      opts = {
        content_type = "application/x-www-form-urlencoded",
        headers=headers
      }
      res = self.client[method](self.client, url, post_data, opts)
    end
  end

  if self.debug then
    pp.dump(res)
  end

  if not res or res.err or not res.body then
    error("Error")
    return nil
  end

  local body = cjson.decode(res.body)
  return body
end

return Gengo

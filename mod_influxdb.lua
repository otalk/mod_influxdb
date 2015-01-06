-- Log common stats to influxdb
--
-- Authors: Marcus Stong
--
-- Contributors: Daurnimator
--
-- This module is MIT/X11 licensed.

local socket = require "socket"
local iterators = require "util.iterators"
local cjson = require "cjson"
local options = module:get_option("influxdb") or {}

-- Create UDP socket to influxdb api
local sock = socket.udp()
sock:setpeername(options.hostname or "127.0.0.1", options.port or 4444)

-- Metrics are namespaced by ".", and seperated by newline
local prefix = (options.prefix or "prosody") .. "."

-- Standard point formatting
function prepare_point(name, point, host)
  local hostname = host or module.host
  table.insert(point.points, hostname)
  if point.columns then
    table.insert(point.columns, "host")
  end

  local point_serialized = {
    name = prefix..name,
    columns = point.columns or { "value", "host" },
    points = { point.points }
  }
  return point_serialized
end

-- A 'safer' send function to expose
function send(s) return sock:send(s) end

-- Reload config changes
module:hook_global("config-reloaded", function()
    sock:setpeername(options.hostname or "127.0.0.1", options.port or 4444)
    prefix = (options.prefix or "prosody") .. "."
    anonymous = options.anonymous or false
end);

-- Track users as they bind/unbind
-- count bare sessions every time, as we have no way to tell if it's a new bare session or not
module:hook("resource-bind", function(event)
    local message = {}
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "bare_sessions", iterators.count(pairs(bare_sessions)) }}))
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "full_sessions", 1 }}))
    send(cjson.encode(message))
end, 1)

module:hook("resource-unbind", function(event)
    local message = {}
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "bare_sessions", iterators.count(pairs(bare_sessions)) }}))
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "full_sessions", 1 }}))
    send(cjson.encode(message))
end, 1)

-- Track MUC occupants as they join/leave
module:hook("muc-occupant-joined", function(event)
    local message = {}
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "n_occupants", 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-occupant-left", function(event)
    local message = {}
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "n_occupants", -1 }}))
    send(cjson.encode(message))
end)

-- Misc other MUC
module:hook("muc-broadcast-message", function(event)
    local message = {}
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "broadcast-message", 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-invite", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "invite", 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-decline", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("stats", { columns = { "metric", "value" }, points = { "decline", 1 }}))
    send(cjson.encode(message))
end)

module:hook("colibri-stats", function(event)
    local message = {}
    -- we'll set this as host in these metrics
    local host = event.bridge
    local name = "jvb"
    local data = {
        columns= {},
        points = {}
    }
    -- iterate over each stat
    for k,v in pairs(event.stats) do
        local value = tonumber(v)
        table.insert(data.columns, k)
        table.insert(data.points, value)
    end
    table.insert(message, prepare_point(name, { columns = data.columns, points = data.points }, host))
    --module:log("info", "colibri series %s: ", serialization.serialize(message))
    send(cjson.encode(message))
end)

module:hook("eventlog-stat", function(event)
    local message = {}
    -- iterate over each stat
    local from = event.from
    local service = event.service
    local name = event.metric
    local value = tonumber(event.value)
    table.insert(message, prepare_point("client", { columns = { "metric", "from", "value" }, points = { name, from, value } }, service))
    --module:log("info", "client series %s: ", serialization.serialize(message))
    send(cjson.encode(message))
end)

module:log("info", "Loaded influxdb module")


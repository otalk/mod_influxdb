-- Log common stats to statsd
--
-- This module is MIT/X11 licensed.

local socket = require "socket"
local iterators = require "util.iterators"
local jid = require "util.jid"
local options = module:get_option("influxdb") or {}

-- Create UDP socket to statsd server
local sock = socket.udp()
sock:setpeername(options.hostname or "127.0.0.1", options.port or 4444)

-- Metrics are namespaced by ".", and seperated by newline
local prefix = (options.prefix or "prosody") .. "."

-- Metrics are namespaced by ".", and seperated by newline
function clean(s) return (s:gsub("[%.:\n]", "_")) end

-- Standard point formatting
function prepare_point(name, point)
  local point = {
    name = prefix..name,
    columns = { 'value', 'host' },
    points = {
      { point, module.host }
    }
  }
  return point
end

-- A 'safer' send function to expose
function send(s) return sock:send(s) end

-- Track users as they bind/unbind
-- count bare sessions every time, as we have no way to tell if it's a new bare session or not
module:hook("resource-bind", function(event)
    local message = {}
    table.insert(message, prepare_point("bare_sessions", iterators.count(pairs(bare_sessions))))
    table.insert(message, prepare_point("full_sessions", 1))
    send(cjson.encode(message))
end, 1)

module:hook("resource-unbind", function(event)
    local message = {}
    table.insert(message, prepare_point("bare_sessions", iterators.count(pairs(bare_sessions))))
    table.insert(message, prepare_point("full_sessions", 1))
    send(cjson.encode(message))
end, 1)

-- Track MUC occupants as they join/leave
module:hook("muc-occupant-joined", function(event)
    local message = {}
    table.insert(message, prepare_point("n_occupants", 1))
    local room_node = jid.split(event.room.jid)
    table.insert(message, prepare_point(clean(room_node)..".occupants", 1))
    send(cjson.encode(message))
end)

module:hook("muc-occupant-left", function(event)
    local message = {}
    table.insert(message, prepare_point("n_occupants", -1))
    local room_node = jid.split(event.room.jid)
    table.insert(message, clean(room_node)..".occupants", -1))
    send(cjson.encode(message))
end)

-- Misc other MUC
module:hook("muc-broadcast-message", function(event)
    local message = {}
    table.insert(message, prepare_point("broadcast-message", 1))
    local room_node = jid.split(event.room.jid)
    table.insert(message, clean(room_node)..".broadcast-message", 1))
    send(cjson.encode(message))
end)

module:hook("muc-invite", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("invite", 1))
    local room_node = jid.split(event.room.jid)
    -- Counts per room
    table.insert(message, clean(room_node)..".invite", 1))
    -- Counts per recipient
    table.insert(message, clean(event.stanza.attr.to)..".invited", 1))
    send(cjson.encode(message))
end)

module:hook("muc-decline", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("decline", 1))
    local room_node = jid.split(event.room.jid)
    -- Counts per room
    table.insert(message, clean(room_node)..".decline", 1))
    -- Counts per sender
    table.insert(message, clean(event.incoming.attr.from)..".declined", 1))
    send(cjson.encode(message))
end)

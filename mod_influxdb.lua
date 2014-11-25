-- Log common stats to influxdb
--
-- Authors: Marcus Stong
--
-- Contributors: Daurnimator
--
-- This module is MIT/X11 licensed.

local socket = require "socket"
local iterators = require "util.iterators"
local jid = require "util.jid"
local cjson = require "cjson"
local options = module:get_option("influxdb") or {}

-- Create UDP socket to influxdb api
local sock = socket.udp()
sock:setpeername(options.hostname or "127.0.0.1", options.port or 4444)

-- Metrics are namespaced by ".", and seperated by newline
local prefix = (options.prefix or "prosody") .. "."

local anonymous = options.anonymous or false

-- Metrics are namespaced by ".", and seperated by newline
function clean(s)
    return (s:gsub("[%.:\n]", "_"))
end

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
    table.insert(message, prepare_point("bare_sessions", { points = { iterators.count(pairs(bare_sessions)) }}))
    table.insert(message, prepare_point("full_sessions", { points = { 1 }}))
    send(cjson.encode(message))
end, 1)

module:hook("resource-unbind", function(event)
    local message = {}
    table.insert(message, prepare_point("bare_sessions", { points = {iterators.count(pairs(bare_sessions)) }}))
    table.insert(message, prepare_point("full_sessions", { points = { 1 }}))
    send(cjson.encode(message))
end, 1)

-- Track MUC occupants as they join/leave
module:hook("muc-occupant-joined", function(event)
    local message = {}
    table.insert(message, prepare_point("n_occupants", { points = { 1 }}))
    local room_node = jid.split(event.room.jid)
    table.insert(message, prepare_point(clean(room_node)..".occupants", { points = { 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-occupant-left", function(event)
    local message = {}
    table.insert(message, prepare_point("n_occupants", { points = { -1 }}))
    local room_node = jid.split(event.room.jid)
    local occupants_name = clean(room_node)..".occupants"
    table.insert(message, prepare_point(occupants_name, { points = { -1 }}))
    send(cjson.encode(message))
end)

-- Misc other MUC
module:hook("muc-broadcast-message", function(event)
    local message = {}
    table.insert(message, prepare_point("broadcast-message", { points = { 1 }}))
    local room_node = jid.split(event.room.jid)
    local broadcast_message_name = clean(room_node)..".broadcast-message"
    table.insert(message, prepare_point(broadcast_message_name, { points = { 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-invite", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("invite", { points = { 1 }}))
    local room_node = jid.split(event.room.jid)
    -- Counts per room
    local invite_name = clean(room_node)..".invite"
    table.insert(message, prepare_point(invite_name, { points = { 1 }}))
    -- Counts per recipient
    local stanza_invite_name = clean(event.stanza.attr.to)..".invited"
    table.insert(message, prepare_point(stanza_invite_name, { points = { 1 }}))
    send(cjson.encode(message))
end)

module:hook("muc-decline", function(event)
    local message = {}
    -- Total count
    table.insert(message, prepare_point("decline", { points = { 1 }}))
    local room_node = jid.split(event.room.jid)
    -- Counts per room
    local room_decline_name = clean(room_node)..".decline"
    table.insert(message, prepare_point(room_decline_name, { points = { 1 }}))
    -- Counts per sender
    local event_declined_name = clean(event.incoming.attr.from)..".declined"
    table.insert(message, prepare_point(event_declined_name, { points = { 1 }}))
    send(cjson.encode(message))
end)

module:hook("colibri-stats", function(event)
    local message = {}
    -- we'll set this as host in these metrics
    local host = event.bridge
    -- iterate over each stat
    for k,v in pairs(event.stats) do
        local name = "jvb."..k
        local value = tonumber(v)
        table.insert(message, prepare_point(name, { points = { value } }, host))
    end
    send(cjson.encode(message))
end)

module:hook("eventlog-stat", function(event)
    local message = {}
    -- iterate over each stat
    local name = event.metric
    local room = event.room
    local value = tonumber(event.value)
    table.insert(message, prepare_point(name, { columns = { "room", "value" }, points = { room, value } }))
    send(cjson.encode(message))
end)

module:log("info", "Loaded influxdb module")


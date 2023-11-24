
local inspect = include "argen/lib/inspect"


-- ------------------------------------------------------------------------
-- consts

local STATUS_SYNED = 0
local STATUS_ACKED = 2
local STATUS_PAIRED = 4


-- ------------------------------------------------------------------------
-- core

-- NB: norns doesn't expose eval but we can cheat!
function eval(s)
  local file, err = io.open("/dev/shm/evalhack", "wb")
  file:write("return "..s)
  file:close()
  return dofile("/dev/shm/evalhack")
end


-- ------------------------------------------------------------------------
-- client

function osc_pair_snd(to, path, rxport)
  print("send pair initiation -> " .. to[1] .. ":" .. to[2] .. "!")

  local platform
  local script
  if norns ~= nil then
    platform = "norns"
    script = norns.state.name
    if rxport == nil then
      rxport = 10111
    end
  elseif seamstress ~= nil then
    platform = "seamstress"
    if rxport == nil then
      rxport = 7777
    end
  end

  local args = {
    platform = platform,
    rxport = rxport,
    script = script,
  }

  osc.send(to, path, {inspect(args)})

  local remote = {
    host = to[1],
    port = to[2],
    status = STATUS_SYNED,
    initiated_by = "local",
  }
  return remote
end


-- ------------------------------------------------------------------------
-- server

function osc_pair_rcv(args, from)
  print("received pair initiation <- " .. from[1] .. ":" .. from[2] .. "!")

  if #args < 1 or type(args[1]) ~= "string" then
    print("error - unexpected pair payload")
    return
  end

  -- inspect-serialized string
  args = eval(args[1])
  if type(args) ~= "table" then
    print("error - unexpected pair payload (deserialized)")
    return
  end

  if args.platform == nil then
    print("error - unknown platform")
    return
  end

  local platform = args.platform
  print("is a " .. platform)

  local rxport
  if args.rxport ~= nil then
    rxport = args.rxport
  else
    if platform == "norns" then
      rxport = 10111
    elseif platform == "seamstress" then
      rxport = 7777
    end
  end

  if rxport == nil then
    print("error - couldn't determine remote RX osc port")
    return
  end

  local script
  if args.script ~= nil then
    script = args.script
    print("remote script is " .. script)
  end

  print("success - valid pair request!")

  local remote = {
    host = from[1],
    port = rxport,
    script = script,
    status = STATUS_SYNED,
    initiated_by = "remote",
  }
  return remote
end

function osc_pair_ack(remote, path)
  print("send pair ack -> " .. remote.host .. ":" .. remote.port .. "!")

  local script
  if norns ~= nil then
    script = norns.state.name
    -- TODO: implement for seamstress
  end

  local args = {
    script = script,
  }

  osc.send({remote.host, remote.port}, path.."/ack", {inspect(args)})
end

function osc_pair_synack(remote, path)
  print("send pair synack -> " .. remote.host .. ":" .. remote.port .. "!")
  osc.send({remote.host, remote.port}, path.."/synack", {})
end

function osc_pair_from_remote(path, args, from)
  local remote = osc_pair_rcv(args, from)
  if remote == nil then
    -- invalid request
    return
  end

  osc_pair_ack(remote, path)

  remote.status = STATUS_ACKED
  return remote
end


-- ------------------------------------------------------------------------
-- stateful fns

local osc_remote

function get_remote()
  return osc_remote
end

function asking_for_pairing(to, path)
  osc_remote = osc_pair_snd(to, path)
end

function asked_for_pairing(path, args, from)
  osc_remote = osc_pair_from_remote(path, args, from)
end

function osc_pair_rcv_ack(path, args, from)
  print("received pair ack <- " .. from[1] .. ":" .. from[2] .. "!")

  if osc_remote == nil then
    print("error - didn't initiate a pairing!")
    return
  end

  if not (osc_remote.host == from[1]) then
    print("error - expected answer from "..osc_remote.host)
    return
  end

  if #args < 1 or type(args[1]) ~= "string" then
    print("error - unexpected pair ack payload")
    return
  end

  -- inspect-serialized string
  args = eval(args[1])
  if type(args) ~= "table" then
    print("error - unexpected pair ack payload (deserialized)")
    return
  end

  if args.script ~= nil then
    print("remote is running script: "..args.script)
  end

  osc_remote.status = STATUS_PAIRED
  print("success - acked")

  osc_pair_synack(osc_remote, path)
end

function osc_pair_rcv_synack(args, from)
  print("received pair synack <- " .. from[1] .. ":" .. from[2] .. "!")

  if osc_remote == nil then
    print("error - wasn't being asked to pair!")
    return
  end

  if not (osc_remote.host == from[1]) then
    print("error - expected answer from "..osc_remote.host)
    return
  end

  osc_remote.status = STATUS_PAIRED

  print("success - pairing complete!")
end

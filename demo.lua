
osc_pairing = include("argen/lib/osc_pairing")


function init()
  osc_pair_snd("norns", 10111, "/pair")
end

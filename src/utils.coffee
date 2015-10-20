_ = require 'underscore'
os = require 'os'

localIpv4Address: ->
    ipv4Address = null
    _.each os.networkInterfaces, (ifaces) =>
        _.each ifaces, (iface) =>
            if 'IPv4' is iface.family and not iface.internal
                ipv4Address = iface.address

    ipv4Address

exports =
    localIpv4Address: localIpv4Address

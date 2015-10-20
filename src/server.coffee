fs = require 'fs'
net = require 'net'
express = require 'express'
http = require 'http'
io = require 'socket.io'
ioClient = require 'socket.io-client'
_ = require 'underscore'
Cache = require 'node-cache'
cron = require 'node-schedule'

class HostsInfoService
    constructor: (config) ->
        {hostsInfo, @logger, @confPath} = config
        @_initCache

    _initCache: (hostsInfo) ->
        @_cache = new Cache
            checkPeriod: 0
        @_initHostsInfoMapping hostsInfo
        that = @
        @_cache.on "set", (host, info) ->
            conf = (require that.confPath).config
            conf['hostsInfo'][host] = info
            confStr = JSON.stringify conf
            fs.writeFile that.confPath, confStr, (err) ->
                if err
                    that.logger.error "error writing conf."

        @_cache.on "del", (host, info) ->
            conf = (require that.confPath).config
            delete conf['hostsInfo'][host]
            confStr = JSON.stringify conf
            fs.writeFile that.confPath, confStr, (err) ->
                if err
                    that.logger.error "error writing conf."

        @_cache.on "flush", ->
            conf = (require that.confPath).config
            delete conf['hostsInfo']
            flushedHostsInfo = {}
            hosts = that._cache.keys()
            if not hosts
                for host in hosts
                    info = that._cache.get host
                    if info is undefined
                        that.logger.error "The stream is undefined of host: #{host}"
                    else
                        flushedHostsInfo[host] = info

            conf['hostsInfo'] = flushedHostsInfo
            confStr = JSON.stringify conf
            fs.writeFile that.confPath, confStr, (err) ->
                if err
                    that.logger.error "error writing conf"


    _initHostsInfo: (mappingDict) ->
        for host, info of mappingDict
            @_cache.set host, streams, (err, success) ->
                if err and not success
                    @logger.error "cache set error with key-value '#{host}:#{JSON.stringify info}': #{err}"

    getInfoOfHost: (host) ->
        @_cache.get host

    getAllHosts: ->
        @_cache.keys

    getStreamOfHost: (host, stream) ->
        info = @_cache.get host
        if not info
            @logger.info "No host #{host} exists."
            return undefined

        streams = info["streams"]
        if not streams
            return undefined
        streams[stream]

    setInfoOfHost: (host, info) ->
        that = @
        succeed = @_cache.set host, info
        if not succeed
            that.logger.error "cache set error with key-value '#{host}:#{JSON.stringify info}': #{err}"
        succeed

    removeHost: (hosts...) ->
        that = @
        @_cache.del hosts, (err, count) ->
            if not err
                that.logger.info "Remove #{JSON.stringify(hosts)} success."

    updateHostStreams: (host, streams) ->
        that = this
        @_cache.get host, (err, info) ->
            if not err
                if value is undefined
                    that.logger.error "The toupdate host is not in the conf."
                else
                    streams = info['streams']

class ConfigServer
    constructor: (config) ->
        {@logger, @port, @tailerPingCron} = config
        @hostsInfoService = new HostsInfoService config


    _buildServer: (config) ->
        app = express()
        staticPath = config.staticPath ? __dirname + '/../'
        app.use express.static staticPath

    _createServer: (config, app) ->
        http.createServer app

    run: ->
        @logger.info 'Starting ConfigServer...'
        app = @_buildServer config
        @http = @_createServer config, app
        that = @
        app.get '/nodesInfo', (req, resp) ->
            hosts = that.hostsInfoService.getAllHosts
            data = {}
            for host in hosts
                data[host] = that.hostsInfoService.getInfoOfHost host
            resp.send JSON.stringify data

        io = io.listen @http.listen @port, "127.0.0.1"
        io.set 'log level', 1
        io.on 'connection', (socket) ->
            socket.on "register", (data) ->
                that.logger.info "TailerServer register: #{JSON.stringify data}."
                succeed = that.hostsInfoService.setInfoOfHost data.host, data
                socket.emit "registerResult",
                    "result?": succeed

        scheduledPingJob = cron.scheduleJob @tailerPingCron, ->
            that.iterPing

    iterPing: ->
        for host in @hostsInfoService.getAllHosts
            info = @hostsInfoService.getInfoOfHost host
            @ping host, info['addr']

    ping: (host, hostAddr) ->
        socket = ioClient.connect hostAddr,
            timeout: 100
            reconnectionAttempts: 2
            forceNew: true

        that = @
        socket.on "connection", ->
            socket.emit "ping", {}
        socket.on "aliveAndSendStreams", (data) ->
            that.hostsInfoService.updateHostStreams host, data
            socket.close
        socket.on "error", ->
            that.logger.error "Connect to host #{host} error."
            socket.close
        socket.on "reconnect_failed", ->
            that.logger.error "Connect to host TailerServer #{host} timeout with 2 attempts. Considered TailerServer is down."
            that.hostsInfoService.removeHost host
            socket.close

exports.ConfigServer = ConfigServer

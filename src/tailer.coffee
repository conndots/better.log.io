fs = require('fs')
io = require('socket.io')
ioClient = require('socket.io-client')
_ = require('underscore')
_s = require('underscore.String')
express = require('express')
http = require('http')
spawn = require('child_process').spawn
os = require('os')
events = require 'events'

class LogTailer
    constructor: (@logPath, @tailerServer, @logger) ->
        @logger.info "Tail #{@logPath} of the stream #{@stream} on host node #{@hostname}"

    tail: ->
        @tail = spawn "tail", "-100f #{@logPath}"
        @tail.stdout.setEncoding "utf8"
        that = @
        @tail.on "exit", (exitCode) ->
            that.logger.info "Tail childprocesss exit with code: #{exitCode}"
            if exitCode not 0
                that.tailerServer.emit "sys", "Error: #{exitCode}"

        breakLine = ''
        @tail.on "data", (data) ->
            lines = breakLine + data.toString
            splits = lines.split "\n"
            if not (S splits[splits.length - 1]).endsWith "\n"
                breakLine = splits[splits.length - 1]
                splits.pop
            for logLine in splits
                that.tailerServer.emit "lineTailed", that.logPath, logLine
        @tail.stderr.on 'data', (data) ->
            that.tailerServer.emit "sys", that.logPath, "Error: #{data.toString()}"

    terminateTail: ->
        if @tail
            @tail.kill "SIGINT"
            @logger.info "#{@logPath} tailing process is terminated."

class TailerServer extends events.EventEmitter
    constructor: (config) ->
        {@configServerAddress, @hostname, @configPort, @tailPort, @streams, @logger} = config

    run: ->
        app = @_buildServer config
        @http = @_createServer config, app
        @_register2ConfServer

        logPathToSubscribedStreams = {}

        that = @
        configIO = io.listen @http.listen @configPort, "127.0.0.1"
        tailIO = io.listen @http.listen @tailPort, "127.0.0.1"

        configIO.on "connection", (socket) ->
            socket.on "ping", (data) ->
                socket.emit "aliveAndSendStreams", that.streams

        @on "lineTailed", (logPath, message) ->
            subscribedStreams = logPathToSubscribedStreams[logPath]
            for stream, subscribeNum of subscribedStreams
                tailIO.in(stream).emit "lineTailed",
                    stream: stream
                    node: that.hostname
                    message: message

        @on "sys", (logPath, errMessage) ->
            that.logger.error "#{logPath} tailer error: #{errMessage}"
            subscribedStreams = logPathToSubscribedStreams[logPath]
            for stream in subscribedStreams
                tailIO.in(stream).emit "err",
                    stream: stream
                    node: that.hostname
                    message: "#{logPath} tailer error: #{errMessage}"

        tailIO.on "connection", (socket) ->
            #The number of sockets subscribing the logpath in the current socket
            socketPathToSubCount = {}
            socket.on "subscribe", (stream) ->
                logPaths = that.streams[stream]
                for logPath in logPaths
                    subscribedStreams = logPathToSubscribedStreams[logPath]
                    if not subscribedStreams
                        subscribedStreams = {}
                        logPathToSubscribedStreams[logPath] = subscribedStreams
                        tailer = new LogTailer logPath, that, that.logger
                        tailer.tail
                        logPathToTailer[logPath] = tailer
                    subCount = subscribedStreams[stream]
                    if not subCount
                        subscribedStreams[stream] = 0
                    subscribedStreams[stream] += 1

                    socketSubCount = socketPathToSubCount[logPath]
                    if not socketSubCount
                        socketPathToSubCount[logPath] = 0
                    socketPathToSubCount[logPath] += 1

                socket.join stream

            socket.on "unsubscribe", (stream) ->
                socket.leave stream
                logPaths = that.streams[stream]
                for logPath in logPaths
                    socketCount = socketPathToSubCount[logPath]
                    if socketCount == 1
                        delete socketPathToSubCount[logPath]
                    else if socketCount > 1
                        socketPathToSubCount[logPath] -= 1

                    subscribedStreams = logPathToSubscribedStreams[logPath]
                    if subscribedStreams
                        streamCount = subscribedStreams[stream]
                        if streamCount == 1
                            delete subscribedStreams[stream]
                        else if streamCount > 1
                            subscribedStreams[stream] -= 1
                        if Object.keys(subscribedStreams).length == 0
                            delete logPathToSubscribedStreams[logPath]
                            tailer = logPathToTailer[logPath]
                            tailer.terminateTail
                            delete logPathToTailer[logPath]

            socket.on "disconnect", ->
                # terminate the tailer process if the socket disconnets and no one subscribe to the speciic tailer
                for logPath, count of socketPathToSubCount
                    subscribedStreams = logPathToSubscribedStreams[logPath]
                    totalCount = 0
                    for stream, streamCount of subscribedStreams
                        totalCount += streamCount
                    if count >= totalCount
                        delete logPathToSubscribedStreams[logPath]
                        tailer = logPathToTailer[logPath]
                        tailer.terminateTail
                        delete logPathToTailer[logPath]


    _buildServer: (config) ->
        app = express()
        staticPath = config.staticPath ? __dirname + '/../'
        app.use express.static staticPath

    _createServer: (config, app) ->
        http.createServer app

    _register2ConfServer: ->
        socket = ioClient.connect @configServerAddress,
            timeout: 100
            reconnectionAttempts: 3
            forceNew: true

        that = @
        socket.on 'connect', ->
            data =
                host: that.hostname
                addr: "http://#{util.localIpv4Address}:#{@port}"
                streams: @streams

            socket.emit 'register', data

        socket.on 'registerResult', (data) ->
            if data["result?"]
                that.logger.info "Register is OK."
            else
                that.logger.error "TailServer #{os.hostname} register to #{@configServerAddress} fails."

            socket.close

        socket.on "reconnect_failed", ->
            that.logger.error "Connect to ConfigServer timeout."
            socket.close
        socket.on "error", ->
            that.logger.error "Connect to ConfigServer error."
            socket.close

exports.TailerServer = TailerServer
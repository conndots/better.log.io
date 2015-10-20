{spawn, exec} = require 'child_process'
fs = require 'fs'

ENV = './node_modules/'
BROWSERIFY = "#{ ENV }browserify/bin/cmd.js"
COFFEE = "#{ ENV }coffee-script/bin/coffee"
MOCHA = "#{ ENV }mocha/bin/mocha"
LESS = "#{ ENV }less/bin/lessc"
NODE = "~/bin/node"

TEMPLATE_SRC = "#{ __dirname }/templates"
TEMPLATE_OUTPUT = "#{ __dirname }/src/templates.coffee"

task 'build', 'Builds rtail.io package', ->
    invoke 'templates'
    invoke 'compile'
    invoke 'watch'
    invoke 'less'
    invoke 'browserify'
    # Ensure browserify has completed
    setTimeout(-> invoke 'func_test'), 2000

task 'compile', "Compiles CoffeeScript src/*.coffee to lib/*.js", ->
    console.log "Compiling src/*.coffee to lib/*.js"
    exec "#{COFFEE} --compile --output #{__dirname}/lib/ #{__dirname}/src/", (err, stdout, stderr) ->
        throw err if err
        console.log stdout + stderr if stdout + stderr

task 'watch', "Watch and update CoffeeScript src/*.coffee to lib/*.js", ->
    console.log "Watching src/*.coffee to lib/*.js"
    exec "#{COFFEE} --watch --output #{__dirname}/lib/ #{__dirname}/src/", (err, stdout, stderr) ->
        throw err if err
        console.log stdout + stderr if stdout + stderr

task 'browserify', "Compiles client.coffee to browser-friendly JS", ->
    console.log "Browserifying src/client.coffee to lib/rtail.io.js"
    exec "#{BROWSERIFY} src/client.coffee --exports process,require -o #{ __dirname }/lib/rtail.io.js", (err, stdout, stderr) ->
        throw err if err
        console.log stdout + stderr if err

task "templates", "Compiles templates/*.html to src/templates.coffee", ->
    console.log "Generating src/templates.coffee from templates/*.html"
    buildTemplate()

task "func_test", "Compiles & runs functional tests in test/", ->
    console.log "Compiling test/*.coffee to test/lib/*.js..."
    exec "#{COFFEE} --compile --output #{__dirname}/test/lib/ #{__dirname}/test/", (err, stdout, stderr) ->
        throw err if err
        console.log stdout + stderr if stdout + stderr
        console.log "Running tests..."
        exec "#{MOCHA} --reporter spec test/lib/functional.js", (err, stdout, stderr) ->
            throw err if err
            console.log stdout + stderr if stdout + stderr

exportify = (f) ->
    templateName = f.replace '.html', ''
    templateExportName = templateName.replace '-', '.'
    templateFilePath = "#{ TEMPLATE_SRC }/#{ f }"
    body = fs.readFileSync templateFilePath, 'utf-8'
    content = "exports.#{ templateExportName } = \"\"\"#{ body }\"\"\""

buildTemplate = ->
    files = f.readdirSync TEMPLATE_SRC
    templateBlocks = (exportify f for f in files)
    ontent = '# TEMPLATES.COFFEE IS AUTO-GENERATED. CHANGES WILL BE LOST!\n'
    content += templateBlocks.join '\n\n'
    fs.writeFileSync TEMPLATE_OUTPUT, content, 'utf-8'

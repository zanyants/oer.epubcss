system = require('system')
fs = require('fs')
page = require("webpage").create()

page.onConsoleMessage = (msg, line, source) ->
  console.log "console> " + msg # + " @ line: " + line

if system.args.length != 4
  console.error "This program takes exactly 2 arguments:"
  console.error "URL (for example 'file:///home/my-home/file.xhtml)"
  console.error "CSS/LESS file (for example '/home/my-home/style.css)"
  console.error "Output (X)HTML file"
  phantom.exit 1

cssFile = system.args[1]
address = system.args[2]

# Verify address is an absolute path
# TODO: convert relative paths to absolute ones
if address[0] != '/'
  console.error "Path to HTML file does not seem to be an absolute path. For now it needs to start with a '/'"
  phantom.exit 1
address = "file://#{address}"

outputFile = fs.open(system.args[3], 'w')
outputFile.write '<html xmlns="http://www.w3.org/1999/xhtml">'

lines = 0
page.onAlert = (msg) ->
  if lines++ > 100000
    console.log 'Still Serializing HTML...'
    lines = 0
  outputFile.write msg

console.log "Reading CSS file at: #{cssFile}"
lessFile = fs.read(cssFile, 'utf-8')

console.log "Opening page at: #{address}"
startTime = new Date().getTime()




page.open encodeURI(address), (status) ->
  if status != 'success'
    console.error "File not FOUND!!"
    phantom.exit(1)

  console.log "Loaded? #{status}. Took #{((new Date().getTime()) - startTime) / 1000}s"
  console.log "jQuery loaded..."  if page.injectJs(fs.workingDirectory + '/lib/jquery.js')
  console.log "lesscss loaded..."  if page.injectJs(fs.workingDirectory + '/lib/less-1.3.0.js')
  console.log "custom selectors loaded..."  if page.injectJs(fs.workingDirectory + '/custom.js')
  console.log "epubcss class loaded..."  if page.injectJs(fs.workingDirectory + '/epubcss.js')
  console.log "XHTML-serializer loaded..."  if page.injectJs(fs.workingDirectory + '/lib/dom-to-xhtml.js')

  num = page.evaluate((lessFile) ->
  
    parser = new (window.EpubCSS)()
    parser.emulate(lessFile)

    # Hack to serialize out the HTML (sent to the console)
    console.log 'Serializing (X)HTML back out from WebKit...'
    aryHack =
      push: (str) -> alert str
    
    window.dom2xhtml.serialize($('body')[0], aryHack)

  , lessFile)
  outputFile.flush()
  outputFile.write '</html>'
  outputFile.close()
  phantom.exit()

system = require('system')
fs = require('fs')
page = require("webpage").create()

page.onConsoleMessage = (msg, line, source) ->
  console.log "console> " + msg # + " @ line: " + line

if system.args.length < 6
  console.error "This program takes exactly 5 arguments:"
  console.error "The absolute path to this directory (I know, it's annoying but I need it to load the jquery, mathjax, and the like)"
  console.error "CSS/LESS file (for example '/home/my-home/style.css)"
  console.error "Absolute path to html file (for example '/home/my-home/file.xhtml)"
  console.error "Output (X)HTML file"
  console.error "Output CSS file"
  console.error "Additional config params passed to the EpubCSS constructor:"
  console.error "  debug=true"
  console.error "  autogenerateClasses=false"
  # console.error "  bakeInAllStyles=true"
  phantom.exit 1

programDir = system.args[1]

cssFile = system.args[2]
address = system.args[3]

# Verify address is an absolute path
# TODO: convert relative paths to absolute ones
if address[0] != '/'
  console.error "Path to HTML file does not seem to be an absolute path. For now it needs to start with a '/'"
  phantom.exit 1
address = "file://#{address}"

outputFile = fs.open(system.args[4], 'w')

SPECIAL_CSS_FILE_NAME = '__AUTOGENERATED_CSS_FILE'
outputCSSFile = fs.open(system.args[5], 'w')

config = {}
if system.args.length > 6
  for param in system.args.slice(6)
    [name, value] = param.split('=')
    val = value == 'true'
    config[name] = val



# Alert dumps to the current file
currentFile = { file: outputFile, name: 'Output HTML' }
lines = 0
page.onAlert = (msg) ->
  if lines++ % 100000 == 0
    console.log "Outputting #{currentFile.name} ..."
    lines = lines % 100000
    
  currentFile.file.write msg


LOCK_STATE = {}

# Confirm changes the name of the file
page.onConfirm = (fileName) ->
  # Using indexOf because apparently we can't compare 2 strings in JS if they came from different sources...
  if fileName.indexOf('__PhantomJS_MUTEX') >= 0
    lockName = fileName.split('_')[4]
    if fileName.indexOf('_UNLOCK') >= 0
      delete LOCK_STATE[lockName]
      locks = (key for key of LOCK_STATE)
      if locks.length != 0
        console.log "UNLOCKED '#{lockName}' but still locked on the following: #{ locks }"
      else
        console.log "UNLOCKED '#{lockName}' and Exiting!"
        phantom.exit()
      return true
    else
      console.log "LOCKED '#{lockName}'"
      LOCK_STATE[lockName] = true
    return true
  else if fileName.indexOf('__PhantomJS?') >= 0
    return true
  else if fileName.indexOf(SPECIAL_CSS_FILE_NAME) >= 0
    currentFile.file.close()
    currentFile.file = outputCSSFile
    currentFile.name = "Autogenerated CSS file"
  else if fileName.indexOf('__PhantomJS_MAIN_XHTML_FILE') == 0
    currentFile.file.close()
    currentFile.file = outputFile
    currentFile.name = "Autogenerated XHTML file"
  else
    currentFile.file = fs.open('tempdir/' + fileName, 'w')
    currentFile.name = 'tempdir/' + fileName
  lines = 0
  true

console.log "Reading CSS file at: #{cssFile}"
lessFile = fs.read(cssFile, 'utf-8')

console.log "Opening page at: #{address}"
startTime = new Date().getTime()




page.open encodeURI(address), (status) ->
  if status != 'success'
    console.error "File not FOUND!!"
    phantom.exit(1)

  console.log "Loaded? #{status}. Took #{((new Date().getTime()) - startTime) / 1000}s"
  
  loadScript = (path) ->
    if page.injectJs(path)
    else
      console.error "Could not find #{path}"
      phantom.exit(1)
  
  loadScript(programDir + '/lib/jquery.js')
  loadScript(programDir + '/lib/less-1.3.0.js')
  loadScript(programDir + '/custom.js')
  loadScript(programDir + '/epubcss.js')
  loadScript(programDir + '/rasterize.js')
  loadScript(programDir + '/lib/dom-to-xhtml.js')

  needToKeepWaiting = page.evaluate((lessFile, config, SPECIAL_CSS_FILE_NAME) ->

    callback = () ->
    
      # We need to convert all the canvas elements and images with dataURI's to images
      if config.multipleHTMLFiles
        console.log 'Converting canvas elements and images with DataURI into separate files'
        rasterizer = new (window.Rasterize)(config)
        imagesMap = rasterizer.convert()
        for fileName, dataURI of imagesMap
          confirm fileName
          alert dataURI
    
      parser = new (window.EpubCSS)(config)
      { css:newCSS, files:files } = parser.emulate(lessFile)
  
      # Hack to serialize out the HTML (sent to the console)
      console.log 'Serializing (X)HTML back out from WebKit...'
      aryHack =
        push: (str) -> alert str
      
      confirm '__PhantomJS_MAIN_XHTML_FILE'
      alert '<html xmlns="http://www.w3.org/1999/xhtml">'
      window.dom2xhtml.serialize($('body')[0], aryHack)
      alert '</html>'
      
      confirm(SPECIAL_CSS_FILE_NAME)
      alert(newCSS)
      
      confirm '__PhantomJS_MUTEX_FILES'
      for name, $nodes of files
        confirm name
        alert '<html xmlns="http://www.w3.org/1999/xhtml">'
        alert '<head><link rel="stylesheet" href="style.css"/></head>'
        $nodes.each () ->
          window.dom2xhtml.serialize($(@)[0], aryHack)
        alert '</html>'
      confirm '__PhantomJS_MUTEX_FILES_UNLOCK'

    $math = $('math')
    if $math.length
      console.log "This document has #{$math.length} MathML elements. I hope you got MathJax working because I'm going to wait indefinitely if you didn't!"
      confirm '__PhantomJS_MUTEX_MATHJAX'
      try # Fails if MathJax isn't loaded into the page. So far, it's up to the HTML file to find/include MathJax
        MathJax.Hub.Queue () ->
          callback()
          confirm '__PhantomJS_MUTEX_MATHJAX_UNLOCK'
        return true # needToKeepWaiting
      catch e
        console.error "ERROR Happened"
        console.error e
        confirm '__PhantomJS_MUTEX_MATHJAX_UNLOCK'
    else
      callback()

  , lessFile, config, SPECIAL_CSS_FILE_NAME)

  if not needToKeepWaiting
    currentFile.file.close()
    phantom.exit()

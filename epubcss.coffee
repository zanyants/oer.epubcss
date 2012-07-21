system = require('system')
fs = require('fs')
page = require("webpage").create()

page.onConsoleMessage = (msg, line, source) ->
  console.log "console> " + msg # + " @ line: " + line

if system.args.length != 3
  console.error "This program takes exactly 2 arguments:"
  console.error "URL (for example 'file:///home/my-home/file.xhtml)"
  console.error "CSS/LESS file (for example '/home/my-home/style.css)"
  phantom.exit 1

address = system.args[2]
cssFile = system.args[1]

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
  console.log "lesscss loaded..."  if page.injectJs(fs.workingDirectory + '/lib/less-1.3.0.min.js')

  num = page.evaluate((lessFile) ->
  
    p = new less.Parser()
    p.parse lessFile, (err, ast) ->
      # Now that we have the Less tree
      # Let's do some queries!
      
      mixins = {} # lookup the CSS functions by their selector '.x-funcname'
      
      doStuff = ($context, lessNode, parentSelector, force) ->
        if lessNode instanceof less.tree.Comment then return
        if lessNode instanceof less.tree.mixin.Definition and not force
          mixins[lessNode.name] = lessNode
          return
        if lessNode instanceof less.tree.mixin.Call
          mixin = lessNode.selector.elements[0].value
          #console.log "Looking  [#{parentSelector}] mixin #{ mixin }"
          doStuff $context, mixins[mixin], parentSelector, true # force the mixin to evaluate
          return
        if lessNode instanceof less.tree.Ruleset
  
          $newContext = $('NOT-VALID-TAG') # Hack to create an empty set of matches
          
          # for mixins, don't reset the context
          if force
            $newContext = $context
          
          for selector in lessNode.selectors
            css = ''
            for element in selector.elements
              css += element.combinator.value
              css += element.value
            
            css = css.trim()
            css = css.replace(/::[a-z-]+/, '') # remove the pseudoselectors
            
            startTime = new Date().getTime()
  
            $found = null
            if css[0] == '&'
              # Filter on the 1st arg and then recurse
              filterCss = css.slice(1).trim()
              #console.log "Filter=[#{filterCss}]"
              if filterCss.indexOf(' ') >= 0
                findCss = filterCss.substring(0, filterCss.indexOf(' ') + 1)
                filterCss = filterCss.substring(1, filterCss.indexOf(' ') - 1)
                $found = $context.filter(filterCss).find(findCss)
              else
                $found = $context.filter(filterCss)
            else
              $found = $context.find(css)
            
            $newContext = $newContext.add($found)
  
            endTime = new Date().getTime()
            took = endTime - startTime
            if $found.length or took > 10000
              console.log "Selector [#{parentSelector}] / [#{css}] (#{took/1000}s)  Matches: #{$found.length}"
          
          # Now recurse!
          for rule in lessNode.rules
            doStuff $newContext, rule, parentSelector + ' ' + css
          
          return

        ### If we didn't match the element, then Print out that something fell through ###
        console.warn "Warning: SOmething fell through the cracks!"
        
      for ruleset in ast.rules
        doStuff $('body'), ruleset, ''
  , lessFile)
  phantom.exit()

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
  
    
    # Bind some eval overrides so we can do work
    less.tree.Ruleset.prototype.eval = (env) ->
        # Work up the frames to find a context
        # If we don't find one use body
        skips = 0
        for frame in env.frames
          if skips > 0
            skips -= 1
            continue
          # If it's a definition keep going up the frame stack
          if less.tree.mixin.Definition.prototype.isPrototypeOf(frame)
            skips = frame.frames.length + 1 # Plus one because mixin.Call adds a frame
          else if frame._context and not $context
            $context = frame._context
            parentCSS = frame._parentCSS
        if not $context
          $context = $('body')
          parentCSS = ''
        
        # TODO: Shortcut: If the context is empty we don't need to recurse
        #if not $context.length
        #  return
        
        $newContext = $('NOT-VALID-TAG')
  
        # Loop through and find matches
        if @selectors and @selectors.length
          css = ''
          for selector in @selectors
            css = selector.toCSS()
            
            # Remove pseudoselectors
            css = css.replace(/::[a-z-]+/, '')
    
            startTime = new Date().getTime()
            $found = $context.find(css.trim())
    
            $newContext = $newContext.add($found)
    
            endTime = new Date().getTime()
            took = endTime - startTime
            #if $found.length or took > 10000
            console.log "Selector [#{parentCSS}] / [#{css}] (#{took/1000}s)  Matches: #{$found.length}"
  
          # Push the new set of elements onto the stack
          @_context = $newContext
          @_parentCSS = "#{parentCSS} | #{css} (#{$newContext.length})"
        else
          # If there were no selectors keep the original context
          @_context = $context
          @_parentCSS = parentCSS
        
        ### Run the original eval ###
        tree = less.tree # since the original uses tree
        
        selectors = @selectors and @selectors.map((s) ->
          s.eval env
        )
        ruleset = new (tree.Ruleset)(selectors, @rules.slice(0), @strictImports)
        ### Start: New Code ###
        ruleset._context = @_context
        ruleset._parentCSS = @_parentCSS
        ### End: New Code ###
  
        ruleset.root = @root
        ruleset.allowImports = @allowImports
        env.frames.unshift ruleset
        if ruleset.root or ruleset.allowImports or not ruleset.strictImports
          i = 0
        
          while i < ruleset.rules.length
            Array::splice.apply ruleset.rules, [ i, 1 ].concat(ruleset.rules[i].eval(env))  if ruleset.rules[i] instanceof tree.Import
            i++
        i = 0
        
        while i < ruleset.rules.length
          ruleset.rules[i].frames = env.frames.slice(0)  if ruleset.rules[i] instanceof tree.mixin.Definition
          i++
        i = 0
        
        while i < ruleset.rules.length
          Array::splice.apply ruleset.rules, [ i, 1 ].concat(ruleset.rules[i].eval(env))  if ruleset.rules[i] instanceof tree.mixin.Call
          i++
        i = 0
        rule = undefined
        
        while i < ruleset.rules.length
          rule = ruleset.rules[i]
          ruleset.rules[i] = (if rule.eval then rule.eval(env) else rule)  unless rule instanceof tree.mixin.Definition
          i++
        env.frames.shift()
        ruleset





    
    p = new less.Parser()
    p.parse lessFile, (err, ast) ->
      # Now that we have the Less tree
      # Let's do some queries!
      
      ast.eval {frames:[]}  
  , lessFile)
  phantom.exit()

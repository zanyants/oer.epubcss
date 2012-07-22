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
  console.log "lesscss loaded..."  if page.injectJs(fs.workingDirectory + '/lib/less-1.3.0.js')

  num = page.evaluate((lessFile) ->
  



    tree = less.tree # For when I blindly copy code from lesscss
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

    counterState = {}
    
    logit = (a,b,c) ->
      console.log "TODO: Evaluating", a
      hackValue = "PHIL:SDLKJFH"
      new tree.Quoted('"' + hackValue + '"', hackValue, true, 11235)
    
    evaluators =
      'attr': logit
      'target-counter': logit
      'taget-text': logit
      'pending': logit
    
 
    workQueues =
      'counter-reset': []
      'counter-increment': []
      'content': []
      'move-to': []

    storeIt = (cmd) -> ($el, value) ->
      workQueues[cmd].push($el.data cmd, value)

    complexRules =
      'counter-reset': storeIt 'counter-reset'
              ### This will be done in a later pass. Just store the node
                      defaultNum = 0
                      counters = {}
                      for val in value
                        if less.tree.Expression.prototype.isInstanceOf val
                          name = val.value[0].value
                          num = val.value[1].value
                        else
                          name = val.value
                          num = defaultNum
                        counters[name] = num
                      $el.data 'counter-reset', counters
                      workQueues['counter-reset'].push $el
              ###

      'counter-increment': storeIt 'counter-increment'
      'content': storeIt 'content'

    _oldCallPrototype = less.tree.Call.prototype.eval
    less.tree.Call.prototype.eval = (env) ->
      if @name of evaluators
        args = @args.map (a) -> a.eval(env)
        evaluators[@name] args
      else
        _oldCallPrototype.apply @, [ env ]
    
    less.tree.Rule.prototype.eval = (context) ->
      if @name of complexRules
        for el in context.frames[0]._context
          $el = $(el)
          complexRules[@name] $el, @value.eval(context)
      new(tree.Rule)(@name, @value.eval(context), @important,@index, @inline)
    # less.tree.Expression.prototype.eval = (env) ->
    #less.tree.Quoted.prototype.eval = (env) ->
    #less.tree.Keyword.prototype.eval = (env) ->






    
    p = new less.Parser()
    p.parse lessFile, (err, ast) ->
      # Now that we have the Less tree
      # Let's do some queries!
      
      ast.eval {frames:[]}
      console.log "counter-reset Queue: #{workQueues['counter-reset'].length}"
  , lessFile)
  phantom.exit()

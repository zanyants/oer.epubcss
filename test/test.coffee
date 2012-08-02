$().ready () ->


    PSEUDO_CLASS = "pseudo-element"
    PSEUDO_ELEMENT = "<span class='#{PSEUDO_CLASS}'></span>"
    
    counterState = {}

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
          $context = $(document)
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
            css2 = css.replace(/::[a-z-]+/, '')
    
            startTime = new Date().getTime()
            $found = $context.find(css2.trim())
            
            # If there was a pseudo-selector then add it to the work queue
            if css != css2 and $found.length
              # Create all the pseudo nodes and then use them as $found
              if css.indexOf(':before') >= 0
                pseudos = []
                $found.each () ->
                  $el = $(@)
                  pseudo = $(PSEUDO_ELEMENT).addClass('before')
                  pseudos.push(pseudo.prependTo $el)
                $found = pseudos
              else if css.indexOf(':after') >= 0
                pseudos = []
                $found.each () ->
                  $el = $(@)
                  pseudo = $(PSEUDO_ELEMENT).addClass('after')
                  pseudos.push(pseudo.appendTo $el)
                $found = pseudos
              else
                console.error "Weird pseudo-selector found: #{css}"
    
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
    interestingNodes = {} # Used to know which nodes to squirrel counter information into since someone points to them via target-counter
    
    # Concatenated multiple expressions (evaluated) into 1
    # For example: attr(href) '-title' turns into [ tree.Quoted('#id123'), tree.Quoted('-title') ] and
    # '#id123-title' is returned
    expressionsToString = (args) ->
      # id could be an array of tree.Quoted
      # If so, concatentate
      if less.tree.Expression.prototype.isPrototypeOf args
        args = args.value
      if args instanceof Array
        ret = ''
        for i in args
          if not i
            console.error "BUG: i is not defined!"
          if i.eval2
            ret = ret + i.eval2()
          else
            ret = ret + i.eval().value
        ret
      else
        if args.eval2
          return args.eval2()
        else
          return args.eval().value
    
    evaluators =
      'attr': ($context, args) ->
        # There is only 1 arg, the attribute we need to look up
        href = args[0].value
        id = $context.attr href
        new tree.Quoted('"' + id + '"', id, true, 11235) # Hack because lessCSS uses these frequently?
      'target-counter': ($context, args) ->
        if args.length < 2
          console.error 'target-counter requires at least 2 arguments'
        # This will get evaluated twice;
        # In the 1st pass the id will be added to interestingNodes
        # TODO: In the 2nd pass the counter will be looked up on the node
        id = expressionsToString(args[0])
        counterName = args[1].value
        if id not of interestingNodes
          interestingNodes[id] = false
        return {
          eval: () -> new tree.Anonymous("BUG: target-counter should not be evaluated yet")
          eval2: () ->
            if id of interestingNodes
              counters = interestingNodes[id].data('counters') or {}
              counters[counterName] || 0
        }
      'target-text': ($context, args) ->
        # This will get evaluated twice;
        # In the 1st pass the id will be added to interestingNodes
        # TODO: In the 2nd pass the counter will be looked up on the node
        id = expressionsToString(args[0])
        if id not of interestingNodes
          interestingNodes[id] = false
        return {
          eval: () -> new tree.Anonymous("BUG: target-text should not be evaluated yet")
          eval2: () ->
            # Loop through the node and all the children and generate a text string
            $node = interestingNodes[id]
            contentType = (args[1] || {value: 'content'}).value
            ret = null
            switch contentType
              when 'content-element' then ret = $node.children(":not(.#{PSEUDO_CLASS})").text()
              when 'content-before' then ret = $node.children(".#{PSEUDO_CLASS} .before").text()
              when 'content-after' then ret = $node.children(".#{PSEUDO_CLASS} .after").text()
              when 'content-first-letter' then ret = $node.children(":not(.#{PSEUDO_CLASS})").text().substring(0,1)
              else ret = $node.text()
            ret
        }
      'counter': ($context, args) ->
        # Look up the counter in the global counterState
        return {
          eval: () -> new tree.Anonymous("BUG: counter should not be evaluated yet")
          eval2: () -> counterState[args[0].value] || 0
        }
    
 
    storeIt = (cmd) -> ($el, value) ->
      #console.log "TODO: storing for later: #{cmd} #{$el[0].tagName}", value
      $el.data(cmd, value)

    complexRules =
      'counter-reset': storeIt 'counter-reset'
      'counter-increment': storeIt 'counter-increment'
      'content': storeIt 'content'
      'display': ($el, value) ->
        if 'none' == value
          $el.remove()
        else
          #console.log 'Setting display to something other than none; ignoring'

    _oldCallPrototype = less.tree.Call.prototype.eval
    less.tree.Call.prototype.eval = (env) ->
      if @name of evaluators
        $el = env.frames[0]._context
        args = @args.map (a) -> a.eval(env)
        evaluators[@name]($el, args)
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


    preorderTraverse = ($nodes, func) ->
      $nodes.each () ->
        $node = $(@)
        func($node)
        preorderTraverse($node.children(), func)



    p = less.Parser()
    
    $('.lesscss').on 'change', () ->
    
      p.parse $('.lesscss').val(), (err, lessNode) ->
        env = { frames: [] }
        
        # Initial eval expands all the pseudo nodes, loads up the interestingNodes map, and removes all display:none nodes
        lessNode.eval(env)

        # Now that we have annotated the DOM with styles. Update the nodes.
        
        # Elements with display:none should already have been removed
        # Look up all the interesting nodes given their id (referenced by target-text or target-counter
        for id of interestingNodes
          interestingNodes[id] = $(id)
        
        # Iterate over the DOM and calculate the counter state for each interesting node, adding in pseudo-nodes
        parseCounters = (expr, defaultNum) ->
        
          counters = {}

          # counter-reset can have the following structure: "counter1 counter2 10 counter3 100 counter4 counter5"
          # In this case it's parsed as a tree.Anonymous
          if less.tree.Anonymous.prototype.isPrototypeOf expr
            tokens = expr.value.split(' ')
          else if less.tree.Expression.prototype.isPrototypeOf expr
            tokens = []
            for exp in expr.value
              tokens.push exp.value
          else
            tokens = [expr.value]
          
          i = 0
          while i < tokens.length
            name = tokens[i]
            if i == tokens.length - 1
              val = defaultNum
            else if isNaN(parseInt(tokens[i+1]))
              val = defaultNum
            else
              val = parseInt(tokens[i+1])
              i++
            counters[name] = val
            i++

          counters

        traverseNode = (parseContent) ->
          ($node) ->
            if $node.data('counter-reset')
              counters = parseCounters($node.data('counter-reset'), 0)
              for counter, val of counters
                counterState[counter] = val
            if $node.data('counter-increment')
              counters = parseCounters($node.data('counter-increment'), 1)
              for counter, val of counters
                counterState[counter] = (counterState[counter] || 0) + val
  
            # If this node is an interestingNode then squirrel away the current counter state
            if not parseContent and ('#' + $node.attr('id') of interestingNodes)
              $node.data 'counters', ($.extend {}, counterState)
              interestingNodes['#' + $node.attr('id')] = $node

            # If there is a content: _____ then replace the text contents of the node (not pseudo elements)
            if parseContent and $node.data('content')
              expr = $node.data('content')
              newContent = expressionsToString(expr)
              # Keep the pseudo elements
              pseudoBefore = $node.children('before')
              pseudoAfter = $node.children('after')
              $node.contents().remove()
              $node.prepend pseudoBefore
              $node.append newContent
              $node.append pseudoAfter

        preorderTraverse $('body'), ($node) ->
          (traverseNode false) ($node)

        counterState = {}
        preorderTraverse $('body'), ($node) ->
          (traverseNode true) ($node)
        
        console.log 'Done processing!'

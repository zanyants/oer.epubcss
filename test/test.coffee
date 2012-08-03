$().ready () ->

    ###
    What does this file do?
    -----------------------
    
    This parses a lesscss (or plain CSS) file and emulates certain rules that aren't supported by some HTML browsers
    There are several pieces:
    
    1. Replace lesscss node evaluation for some nodes:
    
    LessCSS offers a great AST for navigating through CSS.
    It has a stack (using env.frames that keeps scoped information)
    We add an additional variable, _context that stores a jQuery set of elements that are currently matched
    So, for a ruleset (selector and rules) the Ruleset.eval maintains a list of elements that currently match the selector.
    Rule.eval is modified to understand rules like counter-increment: and content:
    Call.eval is modified to emulate functions like target-counter(), attr(), etc
    
    2. Special LessCSS Nodes:
    
    Some of these functions cannot be evaluated yet so their evaluation is deferred until later using DeferredEvaluationNode
    (DeferredEvaluationNode.eval() will return itself when it cannot evaluate to something)
    
    The tree.Anonymous node is used to return strings (like the result of counter(chapter) or target-text() )
    
    3. Pseudo Elements ::before and ::after
    
    Pseudo elements are "emulated" because their content: may not be supported by the browser (ie "content: target-text(attr(href))" )
    Also, EPUB documents do not support ::before and ::after
    Pseudo elements are converted to spans with a special class defined by PSEUDO_CLASS.
    
    4. Loops over the document:
    
    The DOM is looped over 3 times:
    - The 1st traversal is done using LessCSS selectors and is used to:
      a. Expand pseudo elements
      b. Remove elements with "display: none"
      c. Sprinkle the special CSS rules on elements (stored in jQuery data())
      d. Find which nodes will need to be looked up later using target-text or target-counter

    - The 2nd traversal is over the entire DOM in order and calculates the state of all the counters
    - The 3rd traversal is also over the entire DOM in order and replaces the content of elements that have a 'content: ...' rule.
    
    ###


    DEBUG_MODIFIED_CLASS = 'debug-epubcss' # Added whenever "content:" is evaluated
    PSEUDO_CLASS = "pseudo-element"
    PSEUDO_ELEMENT = "<span class='#{PSEUDO_CLASS}'></span>"
    
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
            # If the selector does not start with a space then it is a filter
            # ie &:not(.labeled) or &.className
            if css2[0] == ' '
              $found = $context.find(css2.trim())
            else
              $found = $context.filter(css2.trim())
            
            # If there was a pseudo-selector then add it to the work queue
            if css != css2 and $found.length
              # Create all the pseudo nodes and then use them as $found
              if css.indexOf(':before') >= 0
                pseudos = []
                $found.each () ->
                  $el = $(@)
                  # TODO: Merge this pseudo element with an existing on (need to know CSS selector priority)
                  # For now, just remove the previous definition?
                  pseudo = $el.children(".#{PSEUDO_CLASS}.before")
                  if pseudo.length == 0
                    pseudo = $(PSEUDO_ELEMENT).addClass('before')
                  pseudos.push(pseudo.prependTo $el)
                $found = pseudos
              else if css.indexOf(':after') >= 0
                pseudos = []
                $found.each () ->
                  $el = $(@)
                  pseudo = $el.children(".#{PSEUDO_CLASS}.after")
                  if pseudo.length == 0
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

    interestingNodes = {} # Used to know which nodes to squirrel counter information into since someone points to them via target-counter
    
    # Concatenated multiple expressions (evaluated) into 1
    # For example: attr(href) '-title' turns into [ tree.Quoted('#id123'), tree.Quoted('-title') ] and
    # '#id123-title' is returned
    expressionsToString = (env, args) ->
      # id could be an array of tree.Quoted
      # If so, concatentate
      if less.tree.Expression.prototype.isPrototypeOf args
        args = args.value
      if args instanceof Array
        ret = ''
        for i in args
          if not i
            console.error "BUG: i is not defined!"
          ret = ret + expressionsToString(env, i)
        ret
      else
        return args.eval(env).value
    
    class DeferredEvaluationNode
      constructor: (@f) ->
      
      eval: (env) ->
        if env.doNotDefer
          @f(env)
        else
          @
    
    evaluators =
      'attr': (env, args) ->
        return new DeferredEvaluationNode( (env) ->
          $context = env.doNotDefer
          
          # If it's a pseudo-element then use the parent
          if $context.hasClass(PSEUDO_CLASS)
            $context = $context.parent()
          
          # There is only 1 arg, the attribute we need to look up
          href = args[0].eval(env).value
          id = $context.attr href
          if not id
            console.warn "CSS Bug: Could not find attribute '#{href}' on ", $context
          new tree.Anonymous(id or "NO_ID_FOUND_WOOT") # Hack because lessCSS uses these frequently?
        
        ).eval(env)
      'target-counter': (env, args) ->
        if args.length < 2
          console.error 'target-counter requires at least 2 arguments'
        # This will get evaluated twice;
        # In the 1st pass the hrefs of all jQuery element will be added to interestingNodes
        # TODO: In the 2nd pass the counter will be looked up on the node
        for node in env.frames[0]._context
          $node = $(node)
          newEnv =
            doNotDefer: $node
            frames:[{_context:$node}]
          id = expressionsToString(newEnv, args[0])
          interestingNodes[id] = false
        return new DeferredEvaluationNode( (env) ->
          id = expressionsToString(env, args[0])
          counterName = args[1].eval(env).value
          if id of interestingNodes and interestingNodes[id]
            counters = interestingNodes[id].data('counters') or {}
            new tree.Anonymous(counters[counterName] || 0)
        ).eval(env)

      'target-text': (env, args) ->
        # This will get evaluated twice;
        # In the 1st pass the hrefs of all jQuery element will be added to interestingNodes
        # TODO: In the 2nd pass the counter will be looked up on the node
        for node in env.frames[0]._context
          $node = $(node)
          newEnv =
            doNotDefer: $node
            frames:[{_context:$node}]
          id = expressionsToString(newEnv, args[0])
          interestingNodes[id] = false
        return new DeferredEvaluationNode( (env) ->
          id = expressionsToString(env, args[0])
          if interestingNodes[id]
            $node = interestingNodes[id]
            contentType = (args[1] || {value: 'content'}).value
            ret = null
            switch contentType
              when 'content-element' then ret = $node.children(":not(.#{PSEUDO_CLASS})").text()
              when 'content-before' then ret = $node.children(".#{PSEUDO_CLASS} .before").text()
              when 'content-after' then ret = $node.children(".#{PSEUDO_CLASS} .after").text()
              when 'content-first-letter' then ret = $node.children(":not(.#{PSEUDO_CLASS})").text().substring(0,1)
              else ret = $node.text()
            new tree.Anonymous(ret)
        ).eval(env)
      'counter': (env, args) ->
        # Look up the counter in the stored counter state
        return new DeferredEvaluationNode( (env) ->
          $context = env.doNotDefer
          name = args[0].eval(env).value
          val = $context.data('counters')[name]
          new tree.Anonymous(val or 0)
        ).eval(env)
    
 
    storeIt = (cmd) -> ($el, value) ->
      #console.log "TODO: storing for later: #{cmd} #{$el[0].tagName}", value
      $el.data(cmd, value)

    complexRules =
      'counter-reset': storeIt 'counter-reset'
      'counter-increment': storeIt 'counter-increment'
      'content': storeIt 'content'
      'display': ($el, value) ->
        if 'none' == value.eval().value
          $el.remove()
        else
          #console.log 'Setting display to something other than none; ignoring'

    # There are 2 types of calls in lesscss:
    # 1. Macros that are expanded
    # 2. Function calls within content:
    #
    # (1) Should be evaluated during the 1st pass when finding jQuery nodes
    # (2) Should be evaluated during the 1st pass to resolve less variables like @counter-name
    #       and during the last pass (the env should contain only 1 jQuery element)
    #
    _oldCallPrototype = less.tree.Call.prototype.eval
    less.tree.Call.prototype.eval = (env) ->
      if @name of evaluators
        args = @args.map (a) -> a.eval(env)
        evaluators[@name](env, args)
      else
        _oldCallPrototype.apply @, [ env ]
    
    less.tree.Rule.prototype.eval = (env) ->
      if @name of complexRules
        for el in env.frames[0]._context
          $el = $(el)
          complexRules[@name] $el, @value.eval(env)
      new(tree.Rule)(@name, @value.eval(env), @important,@index, @inline)


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

        console.log "----- Looping over all nodes to squirrel away counters to be looked up later"
        counterState = {}
        preorderTraverse $('body'), ($node) ->
            if $node.data('counter-reset')
              counters = parseCounters($node.data('counter-reset'), 0)
              for counter, val of counters
                counterState[counter] = val
            if $node.data('counter-increment')
              counters = parseCounters($node.data('counter-increment'), 1)
              for counter, val of counters
                counterState[counter] = (counterState[counter] || 0) + val
  
            # If this node is an interestingNode then squirrel away the current counter state
            isInteresting = '#' + $node.attr('id') of interestingNodes
            if isInteresting or $node.data('content')
              $node.data 'counters', ($.extend {}, counterState)
            if isInteresting
              interestingNodes['#' + $node.attr('id')] = $node

        console.log "----- Looping over all nodes and updating based on content: "
        counterState = {}
        preorderTraverse $('body'), ($node) ->
            # If there is a content: _____ then replace the text contents of the node (not pseudo elements)
            if $node.data('content')
              $node.addClass(DEBUG_MODIFIED_CLASS)
              env =
                doNotDefer: $node
                frames: [
                  _context: $node
                ]
              expr = $node.data('content')
              newContent = expressionsToString(env, expr)
              console.log "New Content: '#{newContent}' from", expr
              # Keep the pseudo elements
              pseudoBefore = $node.children('.before')
              pseudoAfter = $node.children('.after')
              $node.contents().remove()
              $node.prepend pseudoBefore
              $node.append newContent
              $node.append pseudoAfter
        
        console.log 'Done processing!'

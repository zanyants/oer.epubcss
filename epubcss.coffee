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


### ############ Util Functions ########### ###
# These are used to format numbers and aren't terribly interesting

# convert integer to Roman numeral. From http://www.diveintopython.net/unit_testing/romantest.html
toRoman = (num) ->
  romanNumeralMap = [
    ['M',  1000]
    ['CM', 900]
    ['D',  500]
    ['CD', 400]
    ['C',  100]
    ['XC', 90]
    ['L',  50]
    ['XL', 40]
    ['X',  10]
    ['IX', 9]
    ['V',  5]
    ['IV', 4]
    ['I',  1]
  ]
  if not (0 < num < 5000)
    console.error 'number out of range (must be 1..4999)'
    return num
  
  result = ''
  for [numeral, integer] in romanNumeralMap
    while num >= integer
      result += numeral
      num -= integer
  result

# Options are defined by http://www.w3.org/TR/CSS21/generate.html#propdef-list-style-type
numberingStyle = (num, style='decimal') ->
  switch style
    when 'decimal-leading-zero'
      if num < 10 then "0#{num}"
      else num
    when 'lower-roman'
      toRoman(num).toLowerCase()
    when 'upper-roman'
      toRoman(num)
    when 'lower-latin'
      if not (1 <= num <= 26)
        console.error 'number out of range (must be 1...26)'
      String.fromCharCode(num + 96)
    when 'upper-latin'
      if not (1 <= num <= 26)
        console.error 'number out of range (must be 1...26)'
      String.fromCharCode(num + 64)
    when 'decimal'
      num
    else 
      console.warn "Counter numbering not supported for list type #{style}. Using decimal."
      num



### ############### Override lesscss AST nodes ############### ###

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
      $context = $('html')
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
        css2 = css.replace(/::?before/, '')
        css2 = css2.replace(/::?after/, '')

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
        if $found.length or took > 10000
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
  constructor: (@name, @f) ->
  
  eval: (env) ->
    if env.doNotDefer
      @f(env)
    else
      @

evaluators =
  'attr': (env, args) ->
    return new DeferredEvaluationNode('attr', (env) ->
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
      id = expressionsToString(newEnv, args[0])
      interestingNodes[id] = false
    return new DeferredEvaluationNode('target-counter', (env) ->
      id = expressionsToString(env, args[0])
      counterName = args[1].eval(env).value
      style = 'decimal'
      if args.length > 2
        style = args[2].eval(env).value
      if id of interestingNodes and interestingNodes[id]
        counters = interestingNodes[id].data('counters') or {}
        val = counters[counterName] || 0
        new tree.Anonymous(numberingStyle(val, style))
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
    return new DeferredEvaluationNode('target-text', (env) ->
      id = expressionsToString(env, args[0])
      if interestingNodes[id]
        $node = interestingNodes[id]
        newEnv =
          doNotDefer: $node
        newContent = args[1].eval(newEnv)
        new tree.Anonymous(newContent)
    ).eval(env)
  'counter': (env, args) ->
    # Look up the counter in the stored counter state
    return new DeferredEvaluationNode('counter', (env) ->
      $context = env.doNotDefer
      name = args[0].eval(env).value
      # Defined by http://www.w3.org/TR/CSS21/generate.html#propdef-list-style-type
      style = 'decimal'
      if args.length > 1
        style = args[1].eval(env).value
      val = $context.data('counters')[name]
      new tree.Anonymous(numberingStyle(val or 0, style))
    ).eval(env)
  'string': (env, args) ->
    # Look up the counter in the stored counter state
    return new DeferredEvaluationNode('string', (env) ->
      $context = env.doNotDefer
      name = args[0].eval(env).value
      val = $context.data('strings')[name]
      new tree.Anonymous(val or '')
    ).eval(env)
  # string-set allows content(...)
  'content': (env, args) ->
    return new DeferredEvaluationNode('content', (env) ->
      $node = env.doNotDefer
      contentType = (args[0] || {eval: () -> {value: 'NO_ARGUMENT'}}).eval(env).value
      ret = null
      switch contentType
        when 'NO_ARGUMENT' then ret = $node.contents().filter(() -> 
          @nodeType != 1 or not $(@).hasClass(PSEUDO_CLASS)
          ).text()
        when 'before' then ret = $node.children(".#{PSEUDO_CLASS}.before").text()
        when 'after' then ret = $node.children(".#{PSEUDO_CLASS}.after").text()
        when 'first-letter' then ret = $node.children(":not(.#{PSEUDO_CLASS})").text().substring(0,1)
        else
          console.warn("content() was called with an invalid argument: '#{contentType}'. Assuming no argument was passed in.")
          ret = $node.children(":not(.#{PSEUDO_CLASS})").text()
      new tree.Anonymous(ret)
    ).eval(env)
  # content: allows leader(' . ') for generating '.............' in TOCs
  'leader': (env, args) ->
    new tree.Anonymous(args[0])


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
  'string-set': storeIt 'string-set'

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
  for el in env.frames[0]._context
    $el = $(el)
    value = @value.eval(env)
    
    if @name of complexRules
      complexRules[@name] $el, @value.eval(env)
    else
      # Set a style dictionary if it doesn't already exist
      $el.data('style', {}) if not $el.data('style')
      style = $el.data('style')
      style[@name] = value.toCSS(env)
  new(tree.Rule)(@name, @value.eval(env), @important,@index, @inline)


preorderTraverse = ($nodes, func) ->
  $nodes.each () ->
    $node = $(@)
    func($node)
    preorderTraverse($node.children(), func)



class EpubCSS
  constructor: () ->
  emulate: (cssStr) ->
    p = less.Parser()
    p.parse cssStr, (err, lessNode) ->
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
      stringState = {}
      
      cssHashes = {}
      cssClasses = {}
      cssClassPrefix = 'autogen-'
      cssClassNum = 0

      preorderTraverse $('body'), ($node) ->
          if $node.data('counter-reset')
            counters = parseCounters($node.data('counter-reset'), 0)
            for counter, val of counters
              counterState[counter] = val
          if $node.data('counter-increment')
            counters = parseCounters($node.data('counter-increment'), 1)
            for counter, val of counters
              counterState[counter] = (counterState[counter] || 0) + val
          # String-set works much like "content: " at this point:
          # We need to evaluate the contents of the string to set
          # Some of it may contain a counter() or a content(before)
          if $node.data('string-set')
            stringsExp = $node.data('string-set')
            env =
              doNotDefer: $node
              frames: [
                _context: $node
              ]
            name = expressionsToString(env, stringsExp.value[0])
            val = expressionsToString(env, stringsExp.value[1])
            stringState[name] = val


          # If this node is an interestingNode then squirrel away the current counter state
          isInteresting = '#' + $node.attr('id') of interestingNodes
          if isInteresting or $node.data('content')
            $node.data 'counters', ($.extend {}, counterState)
            $node.data 'strings', ($.extend {}, stringState)
          if isInteresting
            interestingNodes['#' + $node.attr('id')] = $node

          # Generate custom classes that don't match            
          if $node.data('style')
            style = $node.data('style')
            $node.data('style', null) # Detatch the style
            hash = JSON.stringify(style)
            if hash not of cssHashes
              name = cssClassPrefix + (cssClassNum++)
              cssHashes[hash] = name
              cssClasses[name] = style
            else
              name = cssHashes[hash]
            $node.addClass(name)

      console.log "----- Looping over all nodes and updating 'content:' without a target-*"
      setContent = (boolTarget) -> ($node) ->
          # If there is a content: _____ then replace the text contents of the node (not pseudo elements)
          if $node.data('content')
            $node.addClass(DEBUG_MODIFIED_CLASS)
            env =
              doNotDefer: $node
              frames: [
                _context: $node
              ]
            expr = $node.data('content')
            recHasTarget = (expr) ->
              hasTarget = false
              if DeferredEvaluationNode.prototype.isPrototypeOf(expr)
                hasTarget = (expr.name == 'target-text')
              else if less.tree.Expression.prototype.isPrototypeOf expr
                for val in expr.value
                  hasTarget = hasTarget or recHasTarget(val)
              else if expr.value?
                hasTarget = recHasTarget(expr.value)
              hasTarget
            hasTarget = recHasTarget(expr)
            if boolTarget ^ hasTarget
              if hasTarget
                console.log 'Found something with a target!'
                console.log 'AKJshd'
              console.log 'Skipping!'
              return

            newContent = expressionsToString(env, expr)
            # console.log "New Content: '#{newContent}' from", expr
            # Keep the pseudo elements
            pseudoBefore = $node.children('.#{PSEUDO_CLASS}.before')
            #pseudoAfter = $node.children('.#{PSEUDO_CLASS}.after')
            # Don't remove the pseudo elements because otherwise we'll lose the jQuery.data() attached to them
            $node.contents(":not(.#{PSEUDO_CLASS})").remove()
            if pseudoBefore.length
              pseudoBefore.after newContent
            else
              $node.prepend newContent

      preorderTraverse $('body'), setContent(false)
      console.log "----- Looping over all nodes and updating 'content:' with a target-*"
      preorderTraverse $('body'), setContent(true)
      
      console.log 'Done processing!'
      
      ary = []
      for name, props of cssClasses
        vals = []
        for propName, propVal of props
          vals.push("#{propName}: #{propVal};")
        ary.push ".#{name} { #{vals.join('')} }"
      $('<style type="text/css"></style>').append(ary.join('\n')).appendTo('body')


if module?
  module.exports = EpubCSS
else if window?
  window.EpubCSS = EpubCSS

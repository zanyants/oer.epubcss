(function() {

  $().ready(function() {
    var complexRules, counterState, evaluators, logit, p, storeIt, tree, workQueues, _oldCallPrototype;
    tree = less.tree;
    less.tree.Ruleset.prototype.eval = function(env) {
      var $context, $found, $newContext, css, endTime, frame, i, parentCSS, rule, ruleset, selector, selectors, skips, startTime, took, _i, _j, _len, _len2, _ref, _ref2;
      skips = 0;
      _ref = env.frames;
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        frame = _ref[_i];
        if (skips > 0) {
          skips -= 1;
          continue;
        }
        if (less.tree.mixin.Definition.prototype.isPrototypeOf(frame)) {
          skips = frame.frames.length + 1;
        } else if (frame._context && !$context) {
          $context = frame._context;
          parentCSS = frame._parentCSS;
        }
      }
      if (!$context) {
        $context = $('body');
        parentCSS = '';
      }
      $newContext = $('NOT-VALID-TAG');
      if (this.selectors && this.selectors.length) {
        css = '';
        _ref2 = this.selectors;
        for (_j = 0, _len2 = _ref2.length; _j < _len2; _j++) {
          selector = _ref2[_j];
          css = selector.toCSS();
          css = css.replace(/::[a-z-]+/, '');
          startTime = new Date().getTime();
          $found = $context.find(css.trim());
          $newContext = $newContext.add($found);
          endTime = new Date().getTime();
          took = endTime - startTime;
          console.log("Selector [" + parentCSS + "] / [" + css + "] (" + (took / 1000) + "s)  Matches: " + $found.length);
        }
        this._context = $newContext;
        this._parentCSS = "" + parentCSS + " | " + css + " (" + $newContext.length + ")";
      } else {
        this._context = $context;
        this._parentCSS = parentCSS;
      }
      /* Run the original eval
      */
      selectors = this.selectors && this.selectors.map(function(s) {
        return s.eval(env);
      });
      ruleset = new tree.Ruleset(selectors, this.rules.slice(0), this.strictImports);
      /* Start: New Code
      */
      ruleset._context = this._context;
      ruleset._parentCSS = this._parentCSS;
      /* End: New Code
      */
      ruleset.root = this.root;
      ruleset.allowImports = this.allowImports;
      env.frames.unshift(ruleset);
      if (ruleset.root || ruleset.allowImports || !ruleset.strictImports) {
        i = 0;
        while (i < ruleset.rules.length) {
          if (ruleset.rules[i] instanceof tree.Import) {
            Array.prototype.splice.apply(ruleset.rules, [i, 1].concat(ruleset.rules[i].eval(env)));
          }
          i++;
        }
      }
      i = 0;
      while (i < ruleset.rules.length) {
        if (ruleset.rules[i] instanceof tree.mixin.Definition) {
          ruleset.rules[i].frames = env.frames.slice(0);
        }
        i++;
      }
      i = 0;
      while (i < ruleset.rules.length) {
        if (ruleset.rules[i] instanceof tree.mixin.Call) {
          Array.prototype.splice.apply(ruleset.rules, [i, 1].concat(ruleset.rules[i].eval(env)));
        }
        i++;
      }
      i = 0;
      rule = void 0;
      while (i < ruleset.rules.length) {
        rule = ruleset.rules[i];
        if (!(rule instanceof tree.mixin.Definition)) {
          ruleset.rules[i] = (rule.eval ? rule.eval(env) : rule);
        }
        i++;
      }
      env.frames.shift();
      return ruleset;
    };
    counterState = {};
    logit = function(a, b, c) {
      var hackValue;
      hackValue = "PHIL:SDLKJFH";
      return new tree.Quoted('"' + hackValue + '"', hackValue, true, 11235);
    };
    evaluators = {
      'attr': logit,
      'target-counter': logit,
      'taget-text': logit,
      'pending': logit
    };
    workQueues = {
      'counter-reset': [],
      'counter-increment': [],
      'content': [],
      'move-to': []
    };
    storeIt = function(cmd) {
      return function($el, value) {
        return workQueues[cmd].push($el.data(cmd, value));
      };
    };
    complexRules = {
      'counter-reset': storeIt('counter-reset'),
      /* This will be done in a later pass. Just store the node
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
      */
      'counter-increment': storeIt('counter-increment'),
      'content': storeIt('content')
    };
    _oldCallPrototype = less.tree.Call.prototype.eval;
    less.tree.Call.prototype.eval = function(env) {
      var args;
      if (this.name in evaluators) {
        args = this.args.map(function(a) {
          return a.eval(env);
        });
        return evaluators[this.name](args);
      } else {
        return _oldCallPrototype.apply(this, [env]);
      }
    };
    less.tree.Rule.prototype.eval = function(context) {
      var $el, el, _i, _len, _ref;
      if (this.name in complexRules) {
        _ref = context.frames[0]._context;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          el = _ref[_i];
          $el = $(el);
          complexRules[this.name]($el, this.value.eval(context));
        }
      }
      return new tree.Rule(this.name, this.value.eval(context), this.important, this.index, this.inline);
    };
    p = less.Parser();
    return $('.lesscss').on('change', function() {
      return p.parse($('.lesscss').val(), function(err, lessNode) {
        var env;
        env = {
          frames: []
        };
        lessNode.eval(env);
        console.log('Environment', env);
        console.log('lessNode', lessNode);
        console.log("counter-reset Queue: " + workQueues['counter-reset'].length);
        return window.node = lessNode;
      });
    });
  });

}).call(this);

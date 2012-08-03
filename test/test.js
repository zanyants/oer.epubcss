(function() {

  $().ready(function() {
    /*
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
    */
    var DEBUG_MODIFIED_CLASS, DeferredEvaluationNode, PSEUDO_CLASS, PSEUDO_ELEMENT, complexRules, evaluators, expressionsToString, interestingNodes, p, preorderTraverse, storeIt, tree, _oldCallPrototype;
    DEBUG_MODIFIED_CLASS = 'debug-epubcss';
    PSEUDO_CLASS = "pseudo-element";
    PSEUDO_ELEMENT = "<span class='" + PSEUDO_CLASS + "'></span>";
    tree = less.tree;
    less.tree.Ruleset.prototype.eval = function(env) {
      var $context, $found, $newContext, css, css2, endTime, frame, i, parentCSS, pseudos, rule, ruleset, selector, selectors, skips, startTime, took, _i, _j, _len, _len2, _ref, _ref2;
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
        $context = $(document);
        parentCSS = '';
      }
      $newContext = $('NOT-VALID-TAG');
      if (this.selectors && this.selectors.length) {
        css = '';
        _ref2 = this.selectors;
        for (_j = 0, _len2 = _ref2.length; _j < _len2; _j++) {
          selector = _ref2[_j];
          css = selector.toCSS();
          css2 = css.replace(/::[a-z-]+/, '');
          startTime = new Date().getTime();
          if (css2[0] === ' ') {
            $found = $context.find(css2.trim());
          } else {
            $found = $context.filter(css2.trim());
          }
          if (css !== css2 && $found.length) {
            if (css.indexOf(':before') >= 0) {
              pseudos = [];
              $found.each(function() {
                var $el, pseudo;
                $el = $(this);
                pseudo = $el.children("." + PSEUDO_CLASS + ".before");
                if (pseudo.length === 0) {
                  pseudo = $(PSEUDO_ELEMENT).addClass('before');
                }
                return pseudos.push(pseudo.prependTo($el));
              });
              $found = pseudos;
            } else if (css.indexOf(':after') >= 0) {
              pseudos = [];
              $found.each(function() {
                var $el, pseudo;
                $el = $(this);
                pseudo = $el.children("." + PSEUDO_CLASS + ".after");
                if (pseudo.length === 0) {
                  pseudo = $(PSEUDO_ELEMENT).addClass('after');
                }
                return pseudos.push(pseudo.appendTo($el));
              });
              $found = pseudos;
            } else {
              console.error("Weird pseudo-selector found: " + css);
            }
          }
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
    interestingNodes = {};
    expressionsToString = function(env, args) {
      var i, ret, _i, _len;
      if (less.tree.Expression.prototype.isPrototypeOf(args)) args = args.value;
      if (args instanceof Array) {
        ret = '';
        for (_i = 0, _len = args.length; _i < _len; _i++) {
          i = args[_i];
          if (!i) console.error("BUG: i is not defined!");
          ret = ret + expressionsToString(env, i);
        }
        return ret;
      } else {
        return args.eval(env).value;
      }
    };
    DeferredEvaluationNode = (function() {

      function DeferredEvaluationNode(f) {
        this.f = f;
      }

      DeferredEvaluationNode.prototype.eval = function(env) {
        if (env.doNotDefer) {
          return this.f(env);
        } else {
          return this;
        }
      };

      return DeferredEvaluationNode;

    })();
    evaluators = {
      'attr': function(env, args) {
        return new DeferredEvaluationNode(function(env) {
          var $context, href, id;
          $context = env.doNotDefer;
          if ($context.hasClass(PSEUDO_CLASS)) $context = $context.parent();
          href = args[0].eval(env).value;
          id = $context.attr(href);
          if (!id) {
            console.warn("CSS Bug: Could not find attribute '" + href + "' on ", $context);
          }
          return new tree.Anonymous(id || "NO_ID_FOUND_WOOT");
        }).eval(env);
      },
      'target-counter': function(env, args) {
        var $node, id, newEnv, node, _i, _len, _ref;
        if (args.length < 2) {
          console.error('target-counter requires at least 2 arguments');
        }
        _ref = env.frames[0]._context;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          node = _ref[_i];
          $node = $(node);
          newEnv = {
            doNotDefer: $node,
            frames: [
              {
                _context: $node
              }
            ]
          };
          id = expressionsToString(newEnv, args[0]);
          interestingNodes[id] = false;
        }
        return new DeferredEvaluationNode(function(env) {
          var counterName, counters;
          id = expressionsToString(env, args[0]);
          counterName = args[1].eval(env).value;
          if (id in interestingNodes && interestingNodes[id]) {
            counters = interestingNodes[id].data('counters') || {};
            return new tree.Anonymous(counters[counterName] || 0);
          }
        }).eval(env);
      },
      'target-text': function(env, args) {
        var $node, id, newEnv, node, _i, _len, _ref;
        _ref = env.frames[0]._context;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          node = _ref[_i];
          $node = $(node);
          newEnv = {
            doNotDefer: $node,
            frames: [
              {
                _context: $node
              }
            ]
          };
          id = expressionsToString(newEnv, args[0]);
          interestingNodes[id] = false;
        }
        return new DeferredEvaluationNode(function(env) {
          var contentType, ret;
          id = expressionsToString(env, args[0]);
          if (interestingNodes[id]) {
            $node = interestingNodes[id];
            contentType = (args[1] || {
              value: 'content'
            }).value;
            ret = null;
            switch (contentType) {
              case 'content-element':
                ret = $node.children(":not(." + PSEUDO_CLASS + ")").text();
                break;
              case 'content-before':
                ret = $node.children("." + PSEUDO_CLASS + " .before").text();
                break;
              case 'content-after':
                ret = $node.children("." + PSEUDO_CLASS + " .after").text();
                break;
              case 'content-first-letter':
                ret = $node.children(":not(." + PSEUDO_CLASS + ")").text().substring(0, 1);
                break;
              default:
                ret = $node.text();
            }
            return new tree.Anonymous(ret);
          }
        }).eval(env);
      },
      'counter': function(env, args) {
        return new DeferredEvaluationNode(function(env) {
          var $context, name, val;
          $context = env.doNotDefer;
          name = args[0].eval(env).value;
          val = $context.data('counters')[name];
          return new tree.Anonymous(val || 0);
        }).eval(env);
      }
    };
    storeIt = function(cmd) {
      return function($el, value) {
        return $el.data(cmd, value);
      };
    };
    complexRules = {
      'counter-reset': storeIt('counter-reset'),
      'counter-increment': storeIt('counter-increment'),
      'content': storeIt('content'),
      'display': function($el, value) {
        if ('none' === value.eval().value) {
          return $el.remove();
        } else {

        }
      }
    };
    _oldCallPrototype = less.tree.Call.prototype.eval;
    less.tree.Call.prototype.eval = function(env) {
      var args;
      if (this.name in evaluators) {
        args = this.args.map(function(a) {
          return a.eval(env);
        });
        return evaluators[this.name](env, args);
      } else {
        return _oldCallPrototype.apply(this, [env]);
      }
    };
    less.tree.Rule.prototype.eval = function(env) {
      var $el, el, _i, _len, _ref;
      if (this.name in complexRules) {
        _ref = env.frames[0]._context;
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          el = _ref[_i];
          $el = $(el);
          complexRules[this.name]($el, this.value.eval(env));
        }
      }
      return new tree.Rule(this.name, this.value.eval(env), this.important, this.index, this.inline);
    };
    preorderTraverse = function($nodes, func) {
      return $nodes.each(function() {
        var $node;
        $node = $(this);
        func($node);
        return preorderTraverse($node.children(), func);
      });
    };
    p = less.Parser();
    return $('.lesscss').on('change', function() {
      return p.parse($('.lesscss').val(), function(err, lessNode) {
        var counterState, env, id, parseCounters;
        env = {
          frames: []
        };
        lessNode.eval(env);
        for (id in interestingNodes) {
          interestingNodes[id] = $(id);
        }
        parseCounters = function(expr, defaultNum) {
          var counters, exp, i, name, tokens, val, _i, _len, _ref;
          counters = {};
          if (less.tree.Anonymous.prototype.isPrototypeOf(expr)) {
            tokens = expr.value.split(' ');
          } else if (less.tree.Expression.prototype.isPrototypeOf(expr)) {
            tokens = [];
            _ref = expr.value;
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              exp = _ref[_i];
              tokens.push(exp.value);
            }
          } else {
            tokens = [expr.value];
          }
          i = 0;
          while (i < tokens.length) {
            name = tokens[i];
            if (i === tokens.length - 1) {
              val = defaultNum;
            } else if (isNaN(parseInt(tokens[i + 1]))) {
              val = defaultNum;
            } else {
              val = parseInt(tokens[i + 1]);
              i++;
            }
            counters[name] = val;
            i++;
          }
          return counters;
        };
        console.log("----- Looping over all nodes to squirrel away counters to be looked up later");
        counterState = {};
        preorderTraverse($('body'), function($node) {
          var counter, counters, isInteresting, val;
          if ($node.data('counter-reset')) {
            counters = parseCounters($node.data('counter-reset'), 0);
            for (counter in counters) {
              val = counters[counter];
              counterState[counter] = val;
            }
          }
          if ($node.data('counter-increment')) {
            counters = parseCounters($node.data('counter-increment'), 1);
            for (counter in counters) {
              val = counters[counter];
              counterState[counter] = (counterState[counter] || 0) + val;
            }
          }
          isInteresting = '#' + $node.attr('id') in interestingNodes;
          if (isInteresting || $node.data('content')) {
            $node.data('counters', $.extend({}, counterState));
          }
          if (isInteresting) {
            return interestingNodes['#' + $node.attr('id')] = $node;
          }
        });
        console.log("----- Looping over all nodes and updating based on content: ");
        counterState = {};
        preorderTraverse($('body'), function($node) {
          var expr, newContent, pseudoAfter, pseudoBefore;
          if ($node.data('content')) {
            $node.addClass(DEBUG_MODIFIED_CLASS);
            env = {
              doNotDefer: $node,
              frames: [
                {
                  _context: $node
                }
              ]
            };
            expr = $node.data('content');
            newContent = expressionsToString(env, expr);
            console.log("New Content: '" + newContent + "' from", expr);
            pseudoBefore = $node.children('.before');
            pseudoAfter = $node.children('.after');
            $node.contents().remove();
            $node.prepend(pseudoBefore);
            $node.append(newContent);
            return $node.append(pseudoAfter);
          }
        });
        return console.log('Done processing!');
      });
    });
  });

}).call(this);

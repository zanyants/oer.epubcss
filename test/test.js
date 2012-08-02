(function() {

  $().ready(function() {
    var ContinuousEvaluatorNode, PSEUDO_CLASS, PSEUDO_ELEMENT, complexRules, counterState, evaluators, expressionsToString, interestingNodes, p, preorderTraverse, storeIt, tree, _oldCallPrototype;
    PSEUDO_CLASS = "pseudo-element";
    PSEUDO_ELEMENT = "<span class='" + PSEUDO_CLASS + "'></span>";
    counterState = {};
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
    counterState = {};
    interestingNodes = {};
    expressionsToString = function(args) {
      var i, ret, _i, _len;
      if (less.tree.Expression.prototype.isPrototypeOf(args)) args = args.value;
      if (args instanceof Array) {
        ret = '';
        for (_i = 0, _len = args.length; _i < _len; _i++) {
          i = args[_i];
          if (!i) console.error("BUG: i is not defined!");
          if (i.eval2) {
            ret = ret + i.eval2().value;
          } else {
            ret = ret + expressionsToString(i.eval());
          }
        }
        return ret;
      } else {
        if (args.eval2) {
          return args.eval2().value;
        } else {
          return args.eval().value;
        }
      }
    };
    ContinuousEvaluatorNode = (function() {

      function ContinuousEvaluatorNode(f) {
        this.f = f;
      }

      ContinuousEvaluatorNode.prototype.eval = function() {
        var ret;
        ret = this.f();
        if (ret) {
          return ret;
        } else {
          return this;
        }
      };

      ContinuousEvaluatorNode.prototype.eval2 = function() {
        return this.eval();
      };

      return ContinuousEvaluatorNode;

    })();
    evaluators = {
      'attr': function($context, args) {
        var href, id;
        href = args[0].value;
        id = $context.attr(href);
        return new tree.Quoted('"' + id + '"', id, true, 11235);
      },
      'target-counter': function($context, args) {
        var counterName, id;
        if (args.length < 2) {
          console.error('target-counter requires at least 2 arguments');
        }
        id = expressionsToString(args[0]);
        counterName = args[1].value;
        if (!(id in interestingNodes)) interestingNodes[id] = false;
        return new ContinuousEvaluatorNode(function() {
          var counters;
          if (id in interestingNodes && interestingNodes[id]) {
            counters = interestingNodes[id].data('counters') || {};
            return new tree.Anonymous(counters[counterName] || 0);
          }
        });
      },
      'target-text': function($context, args) {
        var id;
        id = expressionsToString(args[0]);
        if (!(id in interestingNodes)) interestingNodes[id] = false;
        return new ContinuousEvaluatorNode(function() {
          var $node, contentType, ret;
          if (id in interestingNodes[id] && interestingNodes[id]) {
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
        });
      },
      'counter': function($context, args) {
        return new ContinuousEvaluatorNode(function() {
          var val;
          val = counterState[args[0].value];
          if (val != null) return new tree.Anonymous(val);
        });
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
      var $el, args;
      if (this.name in evaluators) {
        $el = env.frames[0]._context;
        args = this.args.map(function(a) {
          return a.eval(env);
        });
        return evaluators[this.name]($el, args);
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
        var env, id, parseCounters, traverseNode;
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
        traverseNode = function(parseContent) {
          return function($node) {
            var counter, counters, expr, newContent, pseudoAfter, pseudoBefore, val;
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
            if (!parseContent && ('#' + $node.attr('id') in interestingNodes)) {
              $node.data('counters', $.extend({}, counterState));
              interestingNodes['#' + $node.attr('id')] = $node;
            }
            if (parseContent && $node.data('content')) {
              expr = $node.data('content');
              newContent = expressionsToString(expr);
              console.log("New Content: '" + newContent + "' from", expr);
              pseudoBefore = $node.children('.before');
              pseudoAfter = $node.children('.after');
              $node.contents().remove();
              $node.prepend(pseudoBefore);
              $node.append(newContent);
              return $node.append(pseudoAfter);
            }
          };
        };
        console.log("----- Looping over all nodes to squirrel away counters to be looked up later");
        preorderTraverse($('body'), function($node) {
          return (traverseNode(false))($node);
        });
        console.log("----- Looping over all nodes and updating based on content: ");
        counterState = {};
        preorderTraverse($('body'), function($node) {
          return (traverseNode(true))($node);
        });
        return console.log('Done processing!');
      });
    });
  });

}).call(this);

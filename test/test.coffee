runTest = (expect, html, css) ->
  root = $('#qunit-fixture')
  root[0].innerHTML = html
  p = new (module.exports)()
  p.emulate(css)
  # Remove the debug class
  root.find('.debug-epubcss').removeClass('debug-epubcss')
  root.find('*[class=""]').removeAttr('class')
  equal(root[0].innerHTML, expect)


test 'content_basic', () ->
  css    = """article { content: "pass"; }"""
  html   = """<article>fail</article>"""
  expect = """<article>pass</article>"""
  runTest(expect, html, css)

test 'pseudo_simple', () ->
  css    = """article::before { content: "before"; }
              article::after { content: "after"; }
              """
  html   = """<article>text1<span>text2</span>text3</article>"""
  expect = """<article><span class="pseudo-element before">before</span>text1<span>text2</span>text3<span class="pseudo-element after">after</span></article>"""
  runTest(expect, html, css)

test 'attr', () ->
  css    = """article::before { content: attr(href); }"""
  html   = """<article href="pass">fail</article>"""
  expect = """<article href="pass"><span class="pseudo-element before">pass</span>fail</article>"""
  runTest(expect, html, css)

test 'counter', () ->
  css    = """article { counter-reset: a 10 b c 20; }
              article { counter-increment: a b 2 c; }
              article { content: "a=" counter(a) ",b=" counter(b) ",c=" counter(c); }
              """
  html   = """<article>fail</article>"""
  expect = """<article>a=11,b=2,c=21</article>"""
  runTest(expect, html, css)

test 'target_counter', () ->
  css    = """article        { counter-reset: counter 20; }
              em          { counter-increment: counter; }
              test        { content: target-counter(attr(href), counter); }
              test::before { content: target-counter(attr(href), counter, lower-roman); }
              test::after  { content: target-counter(attr(href), counter, upper-latin); }
              """
  html   = """<article><test href="#correct">text0</test><em id="some-other-test">text1</em><em id="correct">text2</em></article>"""
  expect = """<article><test href="#correct"><span class="pseudo-element before">xxii</span>22<span class="pseudo-element after">V</span></test><em id="some-other-test">text1</em><em id="correct">text2</em></article>"""
  runTest(expect, html, css)

test 'content_replace_and_counter', () ->
  """ This test replaces the content of an element (deleting the child) and increments the child"""
  css    = """test        { counter-increment: counter; }
              article        { content: target-counter(attr(href), counter); }
              article::before { content: target-counter(attr(href), counter); }
              """
  html   = """<article href="#correct"><test id="some-other-test"/><test id="correct"/></article>"""
  expect = """<article href="#correct"><span class="pseudo-element before">0</span>2</article>"""
  runTest(expect, html, css)

test 'display_none', () ->
  css    = """.hide       { display: none; }
              test        { counter-increment: counter; }
              test        { content: counter(counter); }
              """
  html   = """<article><test class="hide">fail</test><test class="hide">fail</test><test>fail</test></article>"""
  expect = """<article><test>1</test></article>"""
  runTest(expect, html, css)

test 'target_text', () ->
  css    = """test          { content: target-text(attr(href), content()); }
              test::before  { content: target-text(attr(href), content(before)); }
              test::after   { content: target-text(attr(href), content(after)); }
              test2::before { content: "BEFORE"; }
              test2::after  { content: "AFTER"; }
              inner::before { content: "B"; }
              inner::after  { content: "D"; }
              hide          { display: none; }
              """
  html   = """<article><test href="#itsme">text1</test><test2 id="itsme">A<inner>C<hide>XXX</hide></inner>E</test2>X</article>"""
  expect = """<article><test href="#itsme"><span class="pseudo-element before">BEFORE</span>ABCDE<span class="pseudo-element after">AFTER</span></test><test2 id="itsme"><span class="pseudo-element before">BEFORE</span>A<inner><span class="pseudo-element before">B</span>C<span class="pseudo-element after">D</span></inner>E<span class="pseudo-element after">AFTER</span></test2>X</article>"""
  runTest(expect, html, css)

test 'target_text_and_counters', () ->
  css    = """test          { content: target-text(attr(href), content()); }
              test::before  { content: target-text(attr(href), content(before)); }
              test::after   { content: target-text(attr(href), content(after)); }
              test2::before { content: "BEFORE"; }
              test2::after  { content: "AFTER"; }
              inner::before { content: "B"; }
              inner::after  { content: "D"; }
              hide          { display: none; }
              """
  html   = """<article><test href="#itsme"/><test2 id="itsme">A<inner>C<hide>XXX</hide></inner>E</test2>X</article>"""
  expect = """<article><test href="#itsme"><span class="pseudo-element before">BEFORE</span>ABCDE<span class="pseudo-element after">AFTER</span></test><test2 id="itsme"><span class="pseudo-element before">BEFORE</span>A<inner><span class="pseudo-element before">B</span>C<span class="pseudo-element after">D</span></inner>E<span class="pseudo-element after">AFTER</span></test2>X</article>"""
  runTest(expect, html, css)

test 'string_set', () ->
  css    = """html          { string-set: test-string "SHOULD NEVER SEE THIS"; }
              article       { string-set: test-string "SIMPLE"; }
              article::before  { content: string(test-string); }
              test::before  { content: string(test-string); }
              test          { string-set: test-string target-text(attr(href), content()) "-text"; }
              test2         { content: string(test-string); }
              """
  html   = """<article><test href="#itsme"></test><test2 id="itsme">A<inner>B</inner>C</test2>X</article>"""
  expect = """<article><span class="pseudo-element before">SIMPLE</span><test href="#itsme"><span class="pseudo-element before">ABC-text</span></test><test2 id="itsme">ABC-text</test2>X</article>"""
  runTest(expect, html, css)

test 'string_set_multiple', () ->
  css    = """html          { string-set: test-string1 "success", test-string2 "SUCCESS"; }
              test  { content: string(test-string1) " " string(test-string2); }
              """
  html   = """<article><test>FAILED</test></article>"""
  expect = """<article><test>success SUCCESS</test></article>"""
  runTest(expect, html, css)

test 'string_set_advanced', () ->
  css    = """test          { string-set: test-string target-text(attr(href), content()) " LOKKING-UP-A-LINK"; }
              test2         { content: string(test-string); }
              """
  html   = """<article><test href="#itsme"/><test2 id="itsme">A<inner>C<hide>XXX</hide></inner>E</test2>X</article>"""
  expect = """<article><test href="#itsme"/><test2 id="itsme">AE</test2>X</article>"""
  runTest(expect, html, css)

test 'move_to', () ->
  css    = """test::before  { move-to: BUCKET1; content: "123"; }
              test          { move-to: BUCKET2; }
              test::after    { move-to: BUCKET1; content: "456";}
              test2::before  { content: pending(BUCKET1); }
              test2::after   { content: pending(BUCKET2); }
              """
  html   = """<article><test>ABC</test>tail1<test2>DEF</test2>tail2</article>"""
  expect = """<article>tail1<test2><span class="pseudo-element before"><span class="pseudo-element before">123</span><span class="pseudo-element after">456</span></span>DEF<span class="pseudo-element after"><test>ABC</test></span></test2>tail2</article>"""
  runTest(expect, html, css)


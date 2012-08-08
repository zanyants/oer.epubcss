(function() {
  var address, cssFile, fs, lessFile, lines, outputFile, page, startTime, system;

  system = require('system');

  fs = require('fs');

  page = require("webpage").create();

  page.onConsoleMessage = function(msg, line, source) {
    return console.log("console> " + msg);
  };

  if (system.args.length !== 4) {
    console.error("This program takes exactly 2 arguments:");
    console.error("URL (for example 'file:///home/my-home/file.xhtml)");
    console.error("CSS/LESS file (for example '/home/my-home/style.css)");
    console.error("Output (X)HTML file");
    phantom.exit(1);
  }

  cssFile = system.args[1];

  address = system.args[2];

  if (address[0] !== '/') {
    console.error("Path to HTML file does not seem to be an absolute path. For now it needs to start with a '/'");
    phantom.exit(1);
  }

  address = "file://" + address;

  outputFile = fs.open(system.args[3], 'w');

  outputFile.write('<html xmlns="http://www.w3.org/1999/xhtml">');

  lines = 0;

  page.onAlert = function(msg) {
    if (lines++ > 100000) {
      console.log('Still Serializing HTML...');
      lines = 0;
    }
    return outputFile.write(msg);
  };

  console.log("Reading CSS file at: " + cssFile);

  lessFile = fs.read(cssFile, 'utf-8');

  console.log("Opening page at: " + address);

  startTime = new Date().getTime();

  page.open(encodeURI(address), function(status) {
    var num;
    if (status !== 'success') {
      console.error("File not FOUND!!");
      phantom.exit(1);
    }
    console.log("Loaded? " + status + ". Took " + (((new Date().getTime()) - startTime) / 1000) + "s");
    if (page.injectJs(fs.workingDirectory + '/lib/jquery.js')) {
      console.log("jQuery loaded...");
    }
    if (page.injectJs(fs.workingDirectory + '/lib/less-1.3.0.js')) {
      console.log("lesscss loaded...");
    }
    if (page.injectJs(fs.workingDirectory + '/custom.js')) {
      console.log("custom selectors loaded...");
    }
    if (page.injectJs(fs.workingDirectory + '/epubcss.js')) {
      console.log("epubcss class loaded...");
    }
    if (page.injectJs(fs.workingDirectory + '/lib/dom-to-xhtml.js')) {
      console.log("XHTML-serializer loaded...");
    }
    num = page.evaluate(function(lessFile) {
      var aryHack, parser;
      parser = new window.EpubCSS();
      parser.emulate(lessFile);
      console.log('Serializing (X)HTML back out from WebKit...');
      aryHack = {
        push: function(str) {
          return alert(str);
        }
      };
      return window.dom2xhtml.serialize($('body')[0], aryHack);
    }, lessFile);
    outputFile.flush();
    outputFile.write('</html>');
    outputFile.close();
    return phantom.exit();
  });

}).call(this);

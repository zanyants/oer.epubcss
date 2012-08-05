// From http://stackoverflow.com/questions/2093355/nth-of-type-in-jquery-sizzle
/**
 * Return true to include current element
 * Return false to exclude current element
 */
$.expr[':']['nth-of-type'] = function(elem, i, match) {
    match[3] = match[3] == "even" ? "2n" : match[3] == "odd" ? "2n+1" : match[3];
    if (match[3].indexOf("n") === -1) return i + 1 == match[3];
    var parts = match[3].split("+");
    return (i + 1 - (parts[1] || 0)) % parseInt(parts[0], 10) === 0;
};

/** My custom selectors (some, like the footer ones will need to be hooked in to our tools) **/
$.expr[':']['first-of-type'] = function(elem, i, match) {
    return i === 0;
};

$.expr[':']['footnote-marker'] = function(elem, i, match) {
    console.warn('Pseudoselector :footnote-marker not supported yet. Not matching anything.');
    return false;
};

$.expr[':']['footnote-call'] = function(elem, i, match) {
    console.warn('Pseudoselector :footnote-call not supported yet. Not matching anything.');
    return false;
};

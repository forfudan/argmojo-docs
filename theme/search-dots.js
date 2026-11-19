// A search for `Command.add_argument` or `result.get_flag()` looks for each part, the
// same way scripts/patch_search.js stores them. elasticlunr splits a query
// at spaces and dashes by default; this adds dots and brackets.
if (window.elasticlunr) {
  window.elasticlunr.tokenizer.setSeperator(/[\s\-.()]+/);
}

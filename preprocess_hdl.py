import re

def preprocess_hdl(code: str):
    """Clean, tokenize, and tag HDL code tokens."""
    HDL_KEYWORDS = {"always", "assign", "begin", "end", "posedge"}
    OPERATORS = {"<=", "=", "+", "-", "*", ";"}

    # Remove comments
    code = re.sub(r"//.*?$|/\*.*?\*/", "", code,
                  flags=re.DOTALL | re.MULTILINE)

    # Normalize whitespace
    code = " ".join(code.split())

    # Tokenize
    tokens = re.split(r"(\W)", code)
    tokens = [t for t in tokens if t.strip()]

    # Tag tokens
    tagged = []
    for t in tokens:
        if t in HDL_KEYWORDS:
            tag = "KEYWORD"
        elif t in OPERATORS:
            tag = "OPERATOR"
        elif t.isidentifier():
            tag = "IDENTIFIER"
        elif t.isdigit():
            tag = "LITERAL"
        else:
            tag = "SYMBOL"
        tagged.append((t, tag))
    return tagged
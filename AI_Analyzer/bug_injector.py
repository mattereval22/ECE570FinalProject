"""
bug_injector.py
----------------------------------------
Generates synthetic bugs in Verilog HDL code to create
a labeled dataset for AI model training.

This module defines multiple realistic bug types, injects
them into clean Verilog code, and returns both the buggy
code and its label. It is used by create_hdl_training_data.py
to generate diverse and meaningful bug samples.
"""

import re
import random
from typing import Tuple


# ----------------------------------------------------------------------
# Bug Type Definitions
# ----------------------------------------------------------------------

BUG_TYPES = {
    "latch_bug": "Missing else/default in combinational logic block (causes unintended latch).",
    "blocking_bug": "Blocking '=' used inside sequential logic instead of non-blocking '<='.",
    "missing_end": "Always block or module missing closing 'end' keyword.",
    "missing_reset": "Sequential block missing reset condition.",
    "unused_signal": "Declared signal never used.",
    "syntax_error": "Malformed syntax (missing semicolon or invalid assignment)."
}


# ----------------------------------------------------------------------
# Bug Injection Logic
# ----------------------------------------------------------------------

def inject_bug(code: str) -> Tuple[str, str]:
    """
    Injects a randomly selected bug type into Verilog code.
    Returns the modified code and the associated bug label.

    Args:
        code (str): Clean Verilog HDL source code.

    Returns:
        (buggy_code, bug_label): tuple of (str, str)
    """

    # Bug transformation functions
    bug_patterns = {
        "latch_bug": lambda c: re.sub(
            r"if\s*\(.*?\)\s*[a-zA-Z_]+\s*=\s*[a-zA-Z_]+;",
            "if (enable) q = d;", c, count=1),

        "blocking_bug": lambda c: c.replace("<=", "=", 1),

        "missing_end": lambda c: re.sub(r"\bend\b", "", c, count=1),

        "missing_reset": lambda c: re.sub(r"if\s*\(rst\)", "", c, count=1),

        "unused_signal": lambda c: c + "\nwire unused_signal;",

        "syntax_error": lambda c: re.sub(r";", "", c, count=1)
    }

    bug_type = random.choice(list(bug_patterns.keys()))
    buggy_code = bug_patterns[bug_type](code)

    return buggy_code, bug_type


# ----------------------------------------------------------------------
# Utility for Manual Testing
# ----------------------------------------------------------------------

if __name__ == "__main__":
    clean_example = """
    module simple_counter(input clk, input rst, output reg [3:0] count);
        always @(posedge clk) begin
            if (rst)
                count <= 0;
            else
                count <= count + 1;
        end
    endmodule
    """

    buggy, bug_type = inject_bug(clean_example)
    print(f"🔧 Bug Type Injected: {bug_type}")
    print(f"🧠 Description: {BUG_TYPES[bug_type]}")
    print("--------- Buggy Code ---------")
    print(buggy)
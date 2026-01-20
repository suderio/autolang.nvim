import sys
import re
import argparse
from collections import Counter
from typing import List, Dict

def generate_trigrams(text: str) -> List[str]:
    """
    Generates a list of trigrams from the given text, matching autolang.nvim logic.
    Logic:
    1. Lowercase text.
    2. Extract words (letters only).
    3. Ignore words with length <= 1.
    4. Pad words with '_' at start and end.
    5. Generate 3-char sequences.
    """
    # Normalize to lowercase
    text = text.lower()
    
    # Extract words. 
    # autolang uses text:gmatch("%a+") which matches letters.
    # In Python regex, \w includes digits and underscores, so we use [^\W\d_] to match only unicode letters.
    words = re.findall(r'[^\W\d_]+', text)
    
    trigram_counts = Counter()
    
    for word in words:
        if len(word) <= 1:
            continue
            
        padded = f"_{word}_"
        # Generate trigrams
        for i in range(len(padded) - 2):
            tri = padded[i:i+3]
            trigram_counts[tri] += 1
            
    # Get top 300
    most_common = trigram_counts.most_common(300)
    return [tri for tri, count in most_common]

def format_lua_table(trigrams: List[str]) -> str:
    """Formats the list of trigrams as a Lua table."""
    lines = ["return {"]
    for tri in trigrams:
        # Escape single quotes if present (rare in trigrams but possible if words included them)
        # autolang logic excludes punctuation so quotes unlikely, but safety first.
        safe_tri = tri.replace("'", "\\'") 
        lines.append(f'    "{safe_tri}",')
    lines.append("}")
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Generate trigram Lua file for autolang.nvim")
    parser.add_argument("input_file", help="Path to input text file (utf-8)")
    parser.add_argument("-o", "--output", help="Path to output Lua file. Defaults to stdout.")
    
    args = parser.parse_args()
    
    try:
        with open(args.input_file, 'r', encoding='utf-8') as f:
            text = f.read()
    except Exception as e:
        sys.stderr.write(f"Error reading file: {e}\n")
        sys.exit(1)
        
    trigrams = generate_trigrams(text)
    lua_content = format_lua_table(trigrams)
    
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(lua_content)
            print(f"Successfully wrote {len(trigrams)} trigrams to {args.output}")
        except Exception as e:
            sys.stderr.write(f"Error writing output: {e}\n")
            sys.exit(1)
    else:
        print(lua_content)

# Usage: python3 scripts/generate_trigrams.py dataset.txt -o lua/autolang/trigrams/eo.lua
if __name__ == "__main__":
    main()

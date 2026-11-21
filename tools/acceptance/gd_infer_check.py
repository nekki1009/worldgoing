"""Read-only, conservative GDScript := preflight. Unknown syntax is a finding."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import re
import sys

class InputError(Exception):
    pass

TOKEN = re.compile(r'''(?P<comment>\#[^\n]*)|(?P<string>"""[\s\S]*?"""|\x27\x27\x27[\s\S]*?\x27\x27\x27|"(?:\\[\s\S]|[^"\\])*"|\x27(?:\\[\s\S]|[^\x27\\])*\x27)|(?P<word>[^\W\d]\w*)|(?P<number>0[xX][\da-fA-F_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)|(?P<op>:=|->|==|!=|<=|>=|\*\*|\S)''', re.UNICODE)

def statements(source):
    tokens = []
    depth = 0
    brackets = []
    previous_end = 0
    current_line = 1
    for m in TOKEN.finditer(source):
        text = m.group()
        gap = source[previous_end:m.start()]
        if '\n' in gap and depth == 0 and tokens and tokens[-1][0] != '\\':
            yield tokens
            tokens = []
        current_line += gap.count('\n')
        line = current_line
        current_line += text.count('\n')
        previous_end = m.end()
        if m.lastgroup == 'comment':
            continue
        end = line + text.count('\n')
        if text in ('"', "'"):
            raise InputError('unterminated string at line %d' % line)
        if m.lastgroup != 'string':
            if text in '([{':
                depth += 1
                brackets.append(text)
            if text in ')]}':
                depth -= 1
                if not brackets or brackets.pop() != {')':'(',']':'[','}':'{'}[text]:
                    raise InputError('mismatched delimiter at line %d' % line)
            if depth < 0: raise InputError('unbalanced delimiter at line %d' % line)
        tokens.append((text, line, end, m.lastgroup))
    if depth: raise InputError('unclosed delimiter')
    if tokens: yield tokens


def read(path, hashes):
    try:
        data = Path(path).read_bytes()
        hashes[str(path)] = hashlib.sha256(data).hexdigest()
        return data.decode('utf-8-sig').replace('\r\n', '\n')
    except (OSError, UnicodeError) as e:
        raise InputError('%s: %s' % (path, e)) from e


def header(text):
    text = text.split('\t')[0].strip()
    if text.startswith('"'):
        try: text = ast.literal_eval(text)
        except (ValueError, SyntaxError) as e: raise InputError('invalid quoted diff path') from e
    if text.startswith(('a/', 'b/')): text = text[2:]
    if text != '/dev/null' and (Path(text).is_absolute() or '..' in Path(text).parts):
        raise InputError('unsafe diff path: ' + text)
    return text


def patches(source):
    """Sparse new-side source preserves actual line numbers, never old declarations."""
    rows = source.splitlines()
    i = 0
    units = []
    current = None
    while i < len(rows):
        row = rows[i]
        if row.startswith('--- '):
            if i + 1 >= len(rows) or not rows[i+1].startswith('+++ '):
                raise InputError('missing +++ header')
            name = header(rows[i+1][4:])
            current = {'file': name, 'lines': {}, 'added': set(), 'hunks': 0}
            units.append(current)
            i += 2
            continue
        if row.startswith('@@'):
            m = re.match(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', row)
            if not m or current is None: raise InputError('invalid hunk header')
            old, new = int(m[2] or 1), int(m[4] or 1)
            number = int(m[3])
            current['hunks'] += 1
            i += 1
            while old or new:
                if i >= len(rows): raise InputError('truncated hunk')
                r = rows[i]
                i += 1
                if r.startswith('\\ No newline'): continue
                if not r or r[0] not in ' +-': raise InputError('invalid hunk row')
                sign = r[0]
                if sign != '+': old -= 1
                if sign != '-':
                    new -= 1
                    if number in current['lines']: raise InputError('overlapping hunks')
                    current['lines'][number] = r[1:]
                    if sign == '+': current['added'].add(number)
                    number += 1
                if old < 0 or new < 0: raise InputError('hunk count mismatch')
            continue
        if row.startswith(('GIT binary patch', 'Binary files', '@@@', '+', '-', ' ')) and row.strip():
            raise InputError('unsupported or malformed diff row: ' + row[:80])
        if row.strip() and not row.startswith(('diff --git ', 'index ', 'new file mode ', 'deleted file mode ', 'old mode ', 'new mode ', 'similarity index ', 'rename from ', 'rename to ', '\\ No newline')):
            raise InputError('unrecognized diff content: ' + row[:80])
        i += 1
    if not units or any(not u['hunks'] for u in units): raise InputError('no unified hunks')
    return [(u['file'], '\n'.join(u['lines'].get(n, '') for n in range(1, max(u['lines'], default=0)+1)), u['added']) for u in units if u['file'] != '/dev/null']


PRIMITIVES = {'int','float','bool','String','StringName','NodePath','Vector2','Vector2i','Vector3','Vector3i','Vector4','Vector4i','Color','Rect2','Rect2i','Quaternion','Basis','Transform2D','Transform3D','Dictionary','Array'}

def safe_literal(tokens):
    """shortcut: only closed literal/constructor expressions; expand when false positives matter."""
    if not tokens: return False
    texts = [t[0] for t in tokens]
    if len(tokens) == 1:
        return tokens[0][3] in ('number', 'string') or texts[0] in ('true','false')
    if len(tokens) == 2 and texts[0] in ('+','-') and tokens[1][3] == 'number': return True
    if texts[0] in ('[','{') and texts[-1] in (']','}'):
        level = 0
        for i, t in enumerate(tokens):
            if t[3] == 'string': continue
            if t[0] in ('[','{'): level += 1
            elif t[0] in (']','}'): level -= 1
            if level == 0 and i != len(tokens)-1: return False
        return all(t[3] in ('number','string') or t[0] in ('true','false','[',']','{','}',',',':','+','-') for t in tokens)
    if texts[0] in PRIMITIVES and texts[1] == '(' and texts[-1] == ')':
        # Only literal arguments: conversions of dynamic expressions still get flagged.
        return all(t[3] in ('number','string') or t[0] in ('true','false',',','+','-') for t in tokens[2:-1])
    return False


def signatures(source):
    # Only file/class-level methods. Never trust a name from a nested class or local scope.
    result = {}
    for s in statements(source):
        text = [t[0] for t in s]
        if 'func' not in text: continue
        k = text.index('func')
        line = source.splitlines()[s[k][1]-1]
        if line.startswith((' ', '\t')): continue
        if k+1 < len(text):
            typ = text[text.index('->')+1] if '->' in text else 'UNKNOWN'
            result[text[k+1]] = typ
    return result


class Project:
    def __init__(self, root, overlays, hashes):
        self.root = Path(root).resolve()
        self.overlays = overlays
        self.hashes = hashes
        self.classes = {}
        excluded = {'.git','.godot','.godot-temp','output','reports','generated','evidence','node_modules','.codex','scratch','tmp','.tools','.visual_captures'}
        for directory, dirs, files in os.walk(self.root, followlinks=False):
            if '.gdignore' in files:
                dirs[:] = []
                continue
            dirs[:] = [d for d in dirs if d not in excluded and not d.startswith('archives_') and not Path(directory,d).is_symlink() and not Path(directory,d).is_junction()]
            for name in files:
                if name.endswith('.gd'):
                    p = Path(directory,name)
                    source = read(p, hashes)
                    self.index(str(p.relative_to(self.root)).replace('\\','/'), source)
        for name, source in overlays.items(): self.index(name, source, replace=True)
    def index(self, name, source, replace=False):
        if replace:
            for key in list(self.classes):
                self.classes[key] = [p for p in self.classes[key] if p != name]
        if not re.search(r'^class_name\s+', source, re.M): return
        for s in statements(source):
            if len(s) >= 2 and s[0][0] == 'class_name':
                self.classes.setdefault(s[1][0], []).append(name)
    def load(self, name):
        if name in self.overlays: return self.overlays[name]
        p = (self.root/name).resolve()
        if not p.is_relative_to(self.root): return ''
        try: return read(p, self.hashes)
        except InputError: return ''


def analyze(name, source, added, project, origin):
    found = []
    own = signatures(source)
    # Nested classes or shadowed callables make unqualified lookup ambiguous.
    if re.search(r'^\s*class\s+\w+', source, re.M): own = {}
    own = {n:t for n,t in own.items() if not re.search(r'(?:var|const)\s+' + re.escape(n) + r'\b|[(,]\s*' + re.escape(n) + r'\s*[:=,)]', source)}
    aliases = {}
    for s in statements(source):
        text = [t[0] for t in s]
        if len(text) == 7 and text[0] == 'const' and text[2] in ('=', ':=') and text[3:5] == ['preload', '('] and text[6] == ')':
            k = text.index('preload')
            if k+2 < len(s) and s[k+2][3] == 'string':
                try:
                    path = ast.literal_eval(s[k+2][0])
                    if path.startswith('res://'): aliases[text[1]] = path[6:]
                except (SyntaxError, ValueError): pass
        for k in range(len(s)-2):
            if text[k] != 'var' or text[k+2] != ':=': continue
            rhs = s[k+3:]
            touched = {n for t in s[k:] for n in range(t[1], t[2]+1)}
            if added is not None and not touched.intersection(added): continue
            if safe_literal(rhs): continue
            rt = [t[0] for t in rhs]
            reason = 'UNKNOWN: RHS cannot be proven concrete; dynamic operations or unsupported syntax'
            if 'in' in rt: reason = 'membership in/not in has inference risk'
            elif '[' in rt or '.' in rt or 'get' in rt:
                reason = 'member/index/get or chained call may produce Variant (conservative)'
            elif any(t in rt for t in ('==','!=','<','>','<=','>=','+','-','*','/','%')):
                reason = 'comparison/arithmetic may contain Variant or UNKNOWN operands'
            # A simple zero-argument call can be proved by an explicit signature.
            typ = 'UNKNOWN'
            if len(rt) == 3 and rt[1:] == ['(',')']: typ = own.get(rt[0], 'UNKNOWN')
            elif len(rt) == 5 and rt[1] == '.' and rt[3:] == ['(',')'] and not source.splitlines()[s[k][1]-1].startswith((' ', '\t')):
                choices = project.classes.get(rt[0], [])
                if rt[0] not in aliases and re.search(r'const\s+' + re.escape(rt[0]) + r'\b', source): choices = []
                path = aliases.get(rt[0]) or (choices[0] if len(choices) == 1 else None)
                if path and not re.search(r'var\s+' + re.escape(rt[0]) + r'\b', source): typ = signatures(project.load(path)).get(rt[2], 'UNKNOWN')
            if typ not in ('UNKNOWN','Variant','dynamic','void'):
                continue
            if '(' in rt and reason.startswith('UNKNOWN'): reason = 'UNKNOWN call: no proven explicit concrete return type'
            found.append({'file':name,'line':s[k][1],'variable':text[k+1],'reason':reason,'expression':' '.join(rt),'input':origin})
    return found


def scan(inputs, root):
    hashes = {}
    units = []
    for path in inputs:
        source = read(path, hashes)
        if Path(path).suffix == '.gd': units.append((str(path),source,None,str(path)))
        else: units.extend((n,s,a,str(path)) for n,s,a in patches(source))
    overlays = {n:s for n,s,a,o in units}
    project = Project(root, overlays, hashes)
    findings = [f for n,s,a,o in units for f in analyze(n,s,a,project,o)]
    return {'acceptance':False,'findings':findings,'count':len(findings),'source_hashes':hashes,'policy':'possible-risk preflight; UNKNOWN is a finding, not compiler equivalence'}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('inputs', nargs='+')
    p.add_argument('--project-root', required=True)
    p.add_argument('--json', action='store_true')
    args = p.parse_args(argv)
    try:
        if not Path(args.project_root).is_dir(): raise InputError('project root is not a directory')
        result = scan(args.inputs,args.project_root)
    except InputError as e:
        print('INPUT_ERROR: ' + str(e),file=sys.stderr)
        return 2
    if args.json: print(json.dumps(result,ensure_ascii=False,indent=2))
    else:
        for f in result['findings']:
            print('%s:%s: %s: %s [%s]' % (f['file'],f['line'],f['variable'],f['reason'],f['expression']))
        print('%d possible risks; preflight only' % result['count'])
    return 1 if result['count'] else 0

if __name__ == '__main__':
    sys.exit(main())

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import gd_infer_check as g

class CheckerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def check(self, source):
        p=self.root/'case.gd'
        p.write_text(source,encoding='utf-8')
        return g.scan([p],self.root)['findings']
    def test_real_cases_and_typed_fixes(self):
        rhs=['reference.get("phase") in ["entered", "joined"]','binding.state.duplicate(true)','binding.state.duplicate(true)']
        self.assertEqual([f['variable'] for f in self.check('\n'.join('var %s := %s'%(n,e) for n,e in zip(['historical','duplicate','mismatch'],rhs)))],['historical','duplicate','mismatch'])
        self.assertEqual(self.check('\n'.join('var x: Dictionary = '+e for e in rhs)),[])
    def test_dynamic_operators_and_unknown(self):
        for e in ['a.b','a[0]','a.get("k").duplicate()','x not in []','x == 2','x + 2','unresolved()','null','x as Foo']:
            with self.subTest(e=e): self.assertEqual(len(self.check('var x := '+e)),1)
    def test_literals_and_comments(self):
        self.assertEqual(self.check('# var bad := a.b\nvar a := "in a[0] # nope"\nvar b := Vector2(1,2)\nvar c := [1,"x"]\nvar d := """long\nvar bad := evil()\n"""'),[])
    def test_scope_and_return_types(self):
        f=self.check('func a() -> int:\n\tvar only_here: int = 2\n\treturn 1\nfunc b():\n\tvar bad := only_here\n\tvar ok := a()\n\tvar unknown := b()')
        self.assertEqual([x['variable'] for x in f],['bad','unknown'])
    def test_cross_file_sources(self):
        (self.root/'dep.gd').write_text('class_name Dep\nstatic func known() -> int:\n\treturn 1\nstatic func bad():\n\tpass')
        f=self.check('const Alias = preload("res://dep.gd")\nvar ok := Alias.known()\nvar bad := Dep.bad()\nvar good := Dep.known()')
        self.assertEqual([x['variable'] for x in f],['bad'])
    def test_patch_numbering_multiline_crlf(self):
        p=self.root/'a.patch'
        p.write_bytes(('--- a/x.gd\n+++ b/x.gd\n@@ -20,3 +20,4 @@\n var context := evil()\n-var gone := evil()\n+var next := (\n+ evil())\n var unchanged := evil()\n').replace('\n','\r\n').encode())
        f=g.scan([p],self.root)['findings']
        self.assertEqual([(x['file'],x['line'],x['variable']) for x in f],[('x.gd',21,'next')])
    def test_context_declaration_changed_rhs(self):
        p=self.root/'a.patch'
        p.write_text('--- a/x.gd\n+++ b/x.gd\n@@ -1,3 +1,3 @@\n var value := (\n- 1\n+ data.get("k")\n )\n')
        self.assertEqual(g.scan([p],self.root)['count'],1)
    def test_added_comments_do_not_select_context(self):
        p=self.root/'a.patch'
        p.write_text('--- a/x.gd\n+++ b/x.gd\n@@ -1,2 +1,3 @@\n var value := (\n+# comment only\n evil())\n')
        self.assertEqual(g.scan([p],self.root)['count'],0)
    def test_new_class_in_other_patch_and_multifile(self):
        p=self.root/'a.patch'
        p.write_text('--- /dev/null\n+++ b/dep.gd\n@@ -0,0 +1,3 @@\n+class_name Fresh\n+static func safe() -> int:\n+ return 1\n--- /dev/null\n+++ b/use.gd\n@@ -0,0 +1,2 @@\n+var x := Fresh.unsafe()\n+var y := Fresh.safe()\n')
        self.assertEqual([x['variable'] for x in g.scan([p],self.root)['findings']],['x'])
    def test_ignore_and_explicit_input(self):
        d=self.root/'output'; d.mkdir(); (d/'broken.gd').write_text('var x := [')
        d=self.root/'hidden'; d.mkdir(); (d/'.gdignore').touch(); p=d/'test.gd'; p.write_text('var x := evil()')
        self.assertEqual(self.check('var a := 1'),[])
        self.assertEqual(g.scan([p],self.root)['count'],1)
    def test_malformed(self):
        for text in ['garbage','--- a/x\n+++ b/x\n@@ -1 +1 @@\n+var x := 1','--- a/x\n+++ b/x\n@@ broken']:
            with self.subTest(text=text), self.assertRaises(g.InputError): g.patches(text)
        with self.assertRaises(g.InputError): self.check('var x := "bad')
    def test_literal_postfix_and_nested_shadow(self):
        for e in ['[1][0]', '{"a":1}["a"]']:
            self.assertEqual(len(self.check('var x := '+e)),1)
        self.assertEqual(len(self.check('func value() -> int:\n\treturn 1\nclass Nested:\n\tfunc value():\n\t\tpass\n\tfunc run():\n\t\tvar x := value()')),1)
        self.assertEqual(len(self.check('func value() -> int:\n\treturn 1\nfunc run(value):\n\tvar x := value()')),1)
    def test_multiple_hunks_and_mismatched_brackets(self):
        p=self.root/'multi.patch'
        p.write_text('--- a/use.gd\n+++ b/use.gd\n@@ -2 +2 @@\n-old\n+var a := dynamic()\n@@ -30 +30 @@\n-old\n+var b := data[0]\n')
        self.assertEqual([x['line'] for x in g.scan([p],self.root)['findings']],[2,30])
        with self.assertRaises(g.InputError): self.check('var x := [{]}]')
        with self.assertRaises(g.InputError): g.patches(p.read_text()+'garbage\n')
    def test_wrapped_preload_is_unknown(self):
        (self.root/'dep.gd').write_text('class_name Dep\nstatic func known() -> int:\n\treturn 1\nclass Nested:\n\tstatic func known():\n\t\tpass')
        for rhs in ['preload("res://dep.gd").Nested','wrap(preload("res://dep.gd"))']:
            self.assertEqual(len(self.check('const Alias = '+rhs+'\nvar x := Alias.known()')),1)
    def test_cli_codes(self):
        p=self.root/'case.gd'
        for source,code in [('var a := 1',0),('var a := unknown()',1)]:
            p.write_text(source)
            r=subprocess.run([sys.executable,'-B',g.__file__,'--project-root',str(self.root),str(p),'--json'],capture_output=True,text=True,timeout=15)
            self.assertEqual(r.returncode,code,r.stderr)
            self.assertFalse(json.loads(r.stdout)['acceptance'])
        r=subprocess.run([sys.executable,'-B',g.__file__,'--project-root',str(self.root),str(self.root/'missing.gd')],capture_output=True,text=True,timeout=15)
        self.assertEqual(r.returncode,2)

if __name__=='__main__': unittest.main()

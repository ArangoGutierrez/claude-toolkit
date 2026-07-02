package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// extractSymbols returns the set of top-level function names, method names,
// and type names declared in the source. Exported and unexported are both
// included. Receiver type names are also included (a test referencing the
// type name is a relevance signal too).
func extractSymbols(path string, src []byte) ([]string, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, path, src, parser.SkipObjectResolution)
	if err != nil {
		return nil, fmt.Errorf("extractSymbols %s: %w", path, err)
	}
	seen := map[string]struct{}{}
	add := func(name string) {
		if name == "" || name == "_" {
			return
		}
		seen[name] = struct{}{}
	}
	for _, decl := range file.Decls {
		switch d := decl.(type) {
		case *ast.FuncDecl:
			add(d.Name.Name)
			if d.Recv != nil {
				for _, f := range d.Recv.List {
					switch t := f.Type.(type) {
					case *ast.Ident:
						add(t.Name)
					case *ast.StarExpr:
						if id, ok := t.X.(*ast.Ident); ok {
							add(id.Name)
						}
					}
				}
			}
		case *ast.GenDecl:
			for _, spec := range d.Specs {
				if ts, ok := spec.(*ast.TypeSpec); ok {
					add(ts.Name.Name)
				}
			}
		}
	}
	out := make([]string, 0, len(seen))
	for k := range seen {
		out = append(out, k)
	}
	return out, nil
}

// extractImports returns the set of package identifiers in scope for this
// file. For `import "net/http"`, "http" is in scope. For `import x "net/http"`,
// "x" is in scope. For `import . "fmt"` and `import _ "side"`, nothing is added.
func extractImports(file *ast.File) map[string]struct{} {
	imports := map[string]struct{}{}
	for _, imp := range file.Imports {
		var name string
		if imp.Name != nil {
			name = imp.Name.Name
		} else {
			p := strings.Trim(imp.Path.Value, `"`)
			if i := strings.LastIndex(p, "/"); i >= 0 {
				name = p[i+1:]
			} else {
				name = p
			}
		}
		if name == "" || name == "_" || name == "." {
			continue
		}
		imports[name] = struct{}{}
	}
	return imports
}

// scoreTestFile parses the test file once and returns everything the caller
// needs to rank and render it. Companion bonus is applied by the caller
// (it depends on the source filename, not the test file).
//
//	score:     3 * len(hits)
//	hits:      sorted list of source-symbol names that appear in the test body
//	testFuncs: count of top-level Test*** functions (cosmetic, used in output)
func scoreTestFile(testPath string, srcSymbols []string) (int, []string, int, error) {
	if len(srcSymbols) == 0 {
		return 0, nil, 0, nil
	}
	src, err := os.ReadFile(testPath)
	if err != nil {
		return 0, nil, 0, fmt.Errorf("scoreTestFile read %s: %w", testPath, err)
	}
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, testPath, src, parser.SkipObjectResolution)
	if err != nil {
		return 0, nil, 0, fmt.Errorf("scoreTestFile parse %s: %w", testPath, err)
	}
	want := map[string]struct{}{}
	for _, s := range srcSymbols {
		want[s] = struct{}{}
	}
	imports := extractImports(file)
	hit := map[string]struct{}{}
	ast.Inspect(file, func(n ast.Node) bool {
		// Skip imported-package selectors: `pkg.X` is a reference to the
		// imported package's X, not to a same-named source symbol.
		if sel, ok := n.(*ast.SelectorExpr); ok {
			if id, ok := sel.X.(*ast.Ident); ok {
				if _, isImport := imports[id.Name]; isImport {
					return false
				}
			}
		}
		id, ok := n.(*ast.Ident)
		if !ok {
			return true
		}
		if _, ok := want[id.Name]; ok {
			hit[id.Name] = struct{}{}
		}
		return true
	})
	hits := make([]string, 0, len(hit))
	for k := range hit {
		hits = append(hits, k)
	}
	sort.Strings(hits)
	testFuncs := 0
	for _, decl := range file.Decls {
		fd, ok := decl.(*ast.FuncDecl)
		if !ok || fd.Recv != nil {
			continue
		}
		if strings.HasPrefix(fd.Name.Name, "Test") {
			testFuncs++
		}
	}
	return len(hit) * 3, hits, testFuncs, nil
}

// rankedEntry is one row of the output: a test file path with its score,
// matched source symbols, and Test*** count (for the cosmetic "N tests" field).
type rankedEntry struct {
	path        string
	score       int
	hits        []string
	testFuncs   int
	isCompanion bool
}

// run is the top-level entry point. It parses srcPath, walks sibling
// *_test.go files, scores each (one AST parse per test file), sorts, and
// writes the advisory lines to stdout in the same shape the bash regex
// path emits.
func run(srcPath string, out io.Writer) error {
	srcBytes, err := os.ReadFile(srcPath)
	if err != nil {
		return fmt.Errorf("run read %s: %w", srcPath, err)
	}
	symbols, err := extractSymbols(srcPath, srcBytes)
	if err != nil {
		return fmt.Errorf("run: %w", err)
	}
	dir := filepath.Dir(srcPath)
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("run readdir %s: %w", dir, err)
	}
	base := filepath.Base(srcPath)
	companion := strings.TrimSuffix(base, ".go") + "_test.go"
	var ranked []rankedEntry
	for _, e := range entries {
		name := e.Name()
		if !strings.HasSuffix(name, "_test.go") || name == base {
			continue
		}
		tfPath := filepath.Join(dir, name)
		score, hits, testFuncs, err := scoreTestFile(tfPath, symbols)
		if err != nil {
			continue // Skip unreadable/unparseable test files; don't fail the run.
		}
		isCompanion := name == companion
		// Companion files are always emitted; non-companions need a real hit.
		if score == 0 && !isCompanion {
			continue
		}
		ranked = append(ranked, rankedEntry{path: tfPath, score: score, hits: hits, testFuncs: testFuncs, isCompanion: isCompanion})
	}
	sort.Slice(ranked, func(i, j int) bool {
		// Companion always ranks first regardless of score (literal companion
		// is the highest-confidence signal; tdd-guard usually catches it first
		// but if it lands in our candidate set, we must surface it).
		if ranked[i].isCompanion != ranked[j].isCompanion {
			return ranked[i].isCompanion
		}
		if ranked[i].score != ranked[j].score {
			return ranked[i].score > ranked[j].score
		}
		return ranked[i].path < ranked[j].path
	})
	for _, r := range ranked {
		hitList := strings.Join(capHits(r.hits, 3), ", ")
		if hitList == "" {
			hitList = "(companion)"
		}
		fmt.Fprintf(out, "  %s (%d tests, references %s)\n", r.path, r.testFuncs, hitList)
	}
	return nil
}

// capHits returns the first n elements of hits, or all of them if shorter.
// Used to keep advisory output readable when many symbols match.
func capHits(hits []string, n int) []string {
	if len(hits) <= n {
		return hits
	}
	return hits[:n]
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: test-dep-map-ast <source.go>")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Stdout); err != nil {
		// Non-zero exit signals the bash orchestrator to fall back to regex.
		os.Exit(1)
	}
}

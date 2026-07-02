package main

import (
	"bytes"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

func TestExtractSymbols_FuncTypeMethod(t *testing.T) {
	src := `package mypkg

import "context"

type Server struct{}

func (s *Server) Start(ctx context.Context) error {
	return nil
}

func (s *Server) stop() {}

func NewServer() *Server { return &Server{} }

func helper() int { return 0 }

type Config struct{ Port int }
`
	got, err := extractSymbols("inline.go", []byte(src))
	if err != nil {
		t.Fatalf("extractSymbols error: %v", err)
	}
	sort.Strings(got)
	want := []string{"Config", "NewServer", "Server", "Start", "helper", "stop"}
	if len(got) != len(want) {
		t.Fatalf("symbol count: got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("symbol[%d]: got %q, want %q", i, got[i], want[i])
		}
	}
}

func TestExtractSymbols_ParseError(t *testing.T) {
	src := `package broken

func Bad(  // unclosed paren
`
	_, err := extractSymbols("broken.go", []byte(src))
	if err == nil {
		t.Fatal("expected parse error, got nil")
	}
}

// writeFile is a test helper that writes data to path inside t.TempDir(),
// failing the test on any IO error.
func writeFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	p := filepath.Join(dir, name)
	if err := os.WriteFile(p, []byte(content), 0644); err != nil {
		t.Fatalf("write %s: %v", p, err)
	}
	return p
}

func TestScoreTestFile_SymbolMatches(t *testing.T) {
	dir := t.TempDir()
	srcPath := writeFile(t, dir, "server.go", `package mypkg

type Server struct{}

func (s *Server) Start() error { return nil }
func (s *Server) Stop() error  { return nil }
`)
	tfPath := writeFile(t, dir, "server_test.go", `package mypkg

import "testing"

func TestStart(t *testing.T) {
	s := &Server{}
	if err := s.Start(); err != nil {
		t.Fatal(err)
	}
}
`)
	srcBytes, err := os.ReadFile(srcPath)
	if err != nil {
		t.Fatalf("read %s: %v", srcPath, err)
	}
	symbols, err := extractSymbols(srcPath, srcBytes)
	if err != nil {
		t.Fatalf("extract: %v", err)
	}
	score, hits, testFuncs, err := scoreTestFile(tfPath, symbols)
	if err != nil {
		t.Fatalf("scoreTestFile: %v", err)
	}
	// Test body references: Server (1), Start (1). Each is a source symbol.
	// Expected hits: 2. Score: 2*3 = 6. No companion bonus (applied by caller).
	if len(hits) != 2 {
		t.Errorf("hits: got %v (len %d), want exactly [Server Start]", hits, len(hits))
	}
	if score != 6 {
		t.Errorf("score: got %d, want 6 (2 hits * 3)", score)
	}
	if testFuncs != 1 {
		t.Errorf("testFuncs: got %d, want 1", testFuncs)
	}
}

func TestRun_RanksByRelevance(t *testing.T) {
	dir := t.TempDir()
	srcPath := writeFile(t, dir, "server.go", `package mypkg

type Server struct{}

func (s *Server) Start() error { return nil }
`)
	// Strong match: companion that references Server + Start.
	writeFile(t, dir, "server_test.go", `package mypkg

import "testing"

func TestStart(t *testing.T) {
	s := &Server{}
	_ = s.Start()
}
`)
	// Weaker match: different topic, only mentions Server in a comment.
	writeFile(t, dir, "other_test.go", `package mypkg

import "testing"

// References Server only in this comment; not in code.
func TestUnrelated(t *testing.T) {
	_ = 1
}
`)
	// Zero match.
	writeFile(t, dir, "zero_test.go", `package mypkg

import "testing"

func TestSomething(t *testing.T) {
	_ = "no relevant symbols"
}
`)
	out := captureRun(t, srcPath)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 1 {
		t.Fatalf("expected exactly 1 line of output (only server_test.go has real symbol references), got %d lines: %q", len(lines), out)
	}
	if !strings.Contains(lines[0], "server_test.go") {
		t.Errorf("top-ranked line should reference server_test.go, got: %q", lines[0])
	}
	if strings.Contains(out, "other_test.go") {
		t.Errorf("other_test.go references Server only in a comment; should be omitted (AST walker ignores comments). Got output:\n%s", out)
	}
	if strings.Contains(out, "zero_test.go") {
		t.Errorf("zero-score test should be omitted, got output:\n%s", out)
	}
}

// captureRun executes run() against srcPath and captures its output as a string.
// Uses an in-memory bytes.Buffer — parallel-safe and unbounded.
func captureRun(t *testing.T, srcPath string) string {
	t.Helper()
	var buf bytes.Buffer
	if err := run(srcPath, &buf); err != nil {
		t.Fatalf("run: %v", err)
	}
	return buf.String()
}

func TestRun_CompanionBonus(t *testing.T) {
	dir := t.TempDir()
	srcPath := writeFile(t, dir, "thing.go", `package mypkg

func Do() {}
`)
	// Companion test references Do (score 3). Companion ranks first by contract.
	writeFile(t, dir, "thing_test.go", `package mypkg

import "testing"

func TestDo(t *testing.T) {
	Do()
}
`)
	// Non-companion test references Do (score 3). Ranks second behind companion.
	writeFile(t, dir, "other_test.go", `package mypkg

import "testing"

func TestOther(t *testing.T) {
	Do()
}
`)
	out := captureRun(t, srcPath)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) < 2 {
		t.Fatalf("expected 2 lines, got: %q", out)
	}
	if !strings.Contains(lines[0], "thing_test.go") {
		t.Errorf("companion should rank first, got line[0]=%q", lines[0])
	}
	if !strings.Contains(lines[1], "other_test.go") {
		t.Errorf("non-companion should rank second, got line[1]=%q", lines[1])
	}
}

func TestScoreTestFile_StdlibImportNotCounted(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "thing.go", `package mypkg

type Server struct{}

func Run() {}
`)
	// Test file uses http.Server (imported) — must NOT match local Server.
	// It DOES call Run() (no selector) — that SHOULD match.
	tfPath := writeFile(t, dir, "stdlib_test.go", `package mypkg

import (
	"net/http"
	"testing"
)

func TestStdlib(t *testing.T) {
	_ = &http.Server{}
	Run()
}
`)
	srcPath := filepath.Join(dir, "thing.go")
	srcBytes, err := os.ReadFile(srcPath)
	if err != nil {
		t.Fatalf("read %s: %v", srcPath, err)
	}
	symbols, err := extractSymbols(srcPath, srcBytes)
	if err != nil {
		t.Fatalf("extract: %v", err)
	}
	score, hits, _, err := scoreTestFile(tfPath, symbols)
	if err != nil {
		t.Fatalf("scoreTestFile: %v", err)
	}
	if len(hits) != 1 || hits[0] != "Run" {
		t.Errorf("hits: got %v, want exactly [Run] (Server must NOT match http.Server)", hits)
	}
	if score != 3 {
		t.Errorf("score: got %d, want 3 (1 hit * 3, no false positive from http.Server)", score)
	}
}

func TestRun_CompanionFirstEvenWithFewerHits(t *testing.T) {
	dir := t.TempDir()
	srcPath := writeFile(t, dir, "service.go", `package mypkg

func A() {}
func B() {}
func C() {}
`)
	// Companion: references only A (1 hit, score 3).
	writeFile(t, dir, "service_test.go", `package mypkg

import "testing"

func TestA(t *testing.T) { A() }
`)
	// Non-companion: references A + B + C (3 hits, score 9).
	writeFile(t, dir, "extras_test.go", `package mypkg

import "testing"

func TestEverything(t *testing.T) {
	A()
	B()
	C()
}
`)
	out := captureRun(t, srcPath)
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) < 2 {
		t.Fatalf("expected 2 lines, got: %q", out)
	}
	if !strings.Contains(lines[0], "service_test.go") {
		t.Errorf("companion must rank first even with fewer hits (1 vs 3), got line[0]=%q", lines[0])
	}
	if !strings.Contains(lines[1], "extras_test.go") {
		t.Errorf("non-companion ranks second, got line[1]=%q", lines[1])
	}
}

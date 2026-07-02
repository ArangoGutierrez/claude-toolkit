# Architect Validation Scripts

> _AI-generated engineering reference material. No project-specific or confidential content._

**Purpose:** Dependency cycle detection, layer violation detection, and complexity analysis
**Last Updated:** 2026-02-15
**Maintainer:** Architect agent

## Overview

This library provides automated validation scripts for architecture quality, covering:
- **Dependency Cycle Detection:** Circular dependency detection across languages
- **Layer Violation Detection:** Architecture boundary enforcement
- **Complexity Metrics:** Cyclomatic complexity, coupling, and cohesion analysis

Each validation includes:
- **Detection Script:** Runnable validation code
- **Thresholds:** When complexity is acceptable vs problematic
- **Remediation:** How to fix violations

---

## Table of Contents

1. [Dependency Cycle Detection](#dependency-cycle-detection)
   - [Go Cycle Detection](#go-cycle-detection)
   - [TypeScript Cycle Detection](#typescript-cycle-detection)
   - [Rust Cycle Detection](#rust-cycle-detection)
   - [Python Cycle Detection](#python-cycle-detection)
2. [Layer Violation Detection](#layer-violation-detection)
   - [Go Layer Validation](#go-layer-validation)
   - [TypeScript Layer Validation](#typescript-layer-validation)
   - [Rust Layer Validation](#rust-layer-validation)
   - [Python Layer Validation](#python-layer-validation)
3. [Complexity Metrics](#complexity-metrics)
   - [Cyclomatic Complexity](#cyclomatic-complexity)
   - [Coupling and Cohesion](#coupling-and-cohesion)
   - [Acceptable Thresholds](#acceptable-thresholds)
4. [API Contract Validation](#api-contract-validation)
   - [OpenAPI/Swagger Validation](#openapiswagger-validation)
   - [gRPC Proto Validation](#grpc-proto-validation)
   - [GraphQL Schema Validation](#graphql-schema-validation)
   - [Breaking Change Detection](#breaking-change-detection)
5. [Performance Checks](#performance-checks)
   - [N+1 Query Detection](#n1-query-detection)
   - [Unbounded Loop Detection](#unbounded-loop-detection)
   - [Memory Pattern Analysis](#memory-pattern-analysis)
6. [Concurrency Checks](#concurrency-checks)
   - [Race Detection](#race-detection)
   - [Deadlock Detection](#deadlock-detection)
   - [Resource Leak Detection](#resource-leak-detection)

---

## Dependency Cycle Detection

### Go Cycle Detection

**Tools:** `go mod graph` + custom cycle detector

**Script:** `scripts/validate-go-cycles.sh`

```bash
#!/usr/bin/env bash
# Detect circular dependencies in Go modules

set -euo pipefail

MODULE_NAME="${1:-.}"
cd "$MODULE_NAME" || exit 1

echo "=== Go Dependency Cycle Detection ==="

# Check if go.mod exists
if [[ ! -f "go.mod" ]]; then
    echo "ERROR: No go.mod found in $MODULE_NAME"
    exit 1
fi

# Generate dependency graph
echo "Analyzing module dependencies..."
go mod graph > /tmp/go-deps.txt

# Detect cycles using awk
awk '
BEGIN {
    cycles = 0
}
{
    edge[$1][$2] = 1
    nodes[$1] = 1
    nodes[$2] = 1
}
END {
    # Floyd-Warshall for cycle detection
    for (k in nodes) {
        for (i in nodes) {
            for (j in nodes) {
                if (edge[i][k] && edge[k][j]) {
                    edge[i][j] = 1
                }
            }
        }
    }

    # Check for self-loops (cycles)
    for (n in nodes) {
        if (edge[n][n]) {
            print "CYCLE DETECTED involving: " n
            cycles++
        }
    }

    if (cycles > 0) {
        print "\nFOUND " cycles " cycle(s)"
        exit 1
    } else {
        print "✓ No dependency cycles detected"
    }
}' /tmp/go-deps.txt

# Internal package cycle detection
echo -e "\nChecking internal package cycles..."

go list -f '{{.ImportPath}}: {{join .Imports " "}}' ./... > /tmp/internal-deps.txt

python3 <<'EOF'
import sys
from collections import defaultdict, deque

deps = defaultdict(list)
with open('/tmp/internal-deps.txt') as f:
    for line in f:
        if ':' not in line:
            continue
        pkg, imports = line.split(':', 1)
        pkg = pkg.strip()
        for imp in imports.strip().split():
            deps[pkg].append(imp)

def find_cycle(graph, start, visited, rec_stack, path):
    visited.add(start)
    rec_stack.add(start)
    path.append(start)

    for neighbor in graph.get(start, []):
        if neighbor not in visited:
            cycle = find_cycle(graph, neighbor, visited, rec_stack, path)
            if cycle:
                return cycle
        elif neighbor in rec_stack:
            # Found cycle
            cycle_start = path.index(neighbor)
            return path[cycle_start:] + [neighbor]

    rec_stack.remove(start)
    path.pop()
    return None

visited = set()
for node in deps:
    if node not in visited:
        cycle = find_cycle(deps, node, visited, set(), [])
        if cycle:
            print("INTERNAL CYCLE DETECTED:")
            print(" -> ".join(cycle))
            sys.exit(1)

print("✓ No internal package cycles detected")
EOF

echo -e "\n=== Go cycle validation passed ==="
```

**Thresholds:**
- **Zero tolerance** for module-level cycles
- **Zero tolerance** for package-level cycles within a module
- Cycles indicate tight coupling and must be refactored

**Remediation:**
1. Extract interface to break dependency
2. Introduce dependency injection
3. Use events/callbacks for decoupling
4. Merge packages if they truly belong together

---

### TypeScript Cycle Detection

**Tools:** `madge --circular`

**Script:** `scripts/validate-ts-cycles.sh`

```bash
#!/usr/bin/env bash
# Detect circular dependencies in TypeScript/JavaScript

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== TypeScript Dependency Cycle Detection ==="

# Check if package.json exists
if [[ ! -f "package.json" ]]; then
    echo "ERROR: No package.json found in $PROJECT_ROOT"
    exit 1
fi

# Install madge if not present
if ! command -v madge &> /dev/null; then
    echo "Installing madge..."
    npm install -g madge
fi

# Find TypeScript config or source directories
if [[ -f "tsconfig.json" ]]; then
    SRC_DIRS=$(jq -r '.compilerOptions.baseUrl // "src"' tsconfig.json)
else
    SRC_DIRS="src"
fi

echo "Analyzing circular dependencies in $SRC_DIRS..."

# Run madge with various configurations
CYCLES_FOUND=0

# Check for circular dependencies
if madge --circular --extensions ts,tsx,js,jsx "$SRC_DIRS" > /tmp/madge-output.txt 2>&1; then
    echo "✓ No circular dependencies detected"
else
    CYCLES_FOUND=1
    echo "CIRCULAR DEPENDENCIES DETECTED:"
    cat /tmp/madge-output.txt
fi

# Generate dependency graph image (requires graphviz)
if command -v dot &> /dev/null; then
    echo "Generating dependency graph..."
    madge --image /tmp/dependency-graph.svg "$SRC_DIRS" || true
    echo "Graph saved to /tmp/dependency-graph.svg"
fi

# Check specific patterns that often cause issues
echo -e "\nChecking barrel file anti-patterns..."
find "$SRC_DIRS" -name "index.ts" -o -name "index.tsx" | while read -r barrel; do
    # Count re-exports
    REEXPORTS=$(grep -c "export.*from" "$barrel" 2>/dev/null || echo "0")
    if [[ $REEXPORTS -gt 10 ]]; then
        echo "WARNING: $barrel has $REEXPORTS re-exports (consider splitting)"
    fi
done

if [[ $CYCLES_FOUND -eq 1 ]]; then
    echo -e "\n=== TypeScript cycle validation FAILED ==="
    exit 1
fi

echo -e "\n=== TypeScript cycle validation passed ==="
```

**Thresholds:**
- **Zero tolerance** for import cycles
- **Warning** for barrel files (index.ts) with >10 re-exports
- Cycles indicate module boundary violations

**Remediation:**
1. Extract shared types to separate module
2. Use dependency inversion (interfaces)
3. Merge modules if they're tightly coupled
4. Break up large barrel files

---

### Rust Cycle Detection

**Tools:** `cargo tree` + custom analysis

**Script:** `scripts/validate-rust-cycles.sh`

```bash
#!/usr/bin/env bash
# Detect circular dependencies in Rust crates

set -euo pipefail

CRATE_ROOT="${1:-.}"
cd "$CRATE_ROOT" || exit 1

echo "=== Rust Dependency Cycle Detection ==="

# Check if Cargo.toml exists
if [[ ! -f "Cargo.toml" ]]; then
    echo "ERROR: No Cargo.toml found in $CRATE_ROOT"
    exit 1
fi

# Cargo prevents circular dependencies at crate level by design
# But we can detect potential issues with module organization

echo "Checking crate dependency tree..."
cargo tree --depth 1 > /tmp/rust-deps.txt
echo "✓ Cargo enforces no circular crate dependencies"

# Check for module cycles within the crate
echo -e "\nAnalyzing internal module structure..."

# Find all mod declarations
find src -name "*.rs" -exec grep -H "^mod " {} \; > /tmp/rust-modules.txt 2>/dev/null || true
find src -name "*.rs" -exec grep -H "^pub mod " {} \; >> /tmp/rust-modules.txt 2>/dev/null || true

# Find all use declarations that reference local modules
find src -name "*.rs" -exec grep -H "^use crate::" {} \; > /tmp/rust-uses.txt 2>/dev/null || true
find src -name "*.rs" -exec grep -H "^use super::" {} \; >> /tmp/rust-uses.txt 2>/dev/null || true

python3 <<'EOF'
import sys
import re
from collections import defaultdict

# Build module dependency graph
deps = defaultdict(set)
modules = set()

# Parse use statements
try:
    with open('/tmp/rust-uses.txt') as f:
        for line in f:
            match = re.match(r'([^:]+):\s*use\s+(crate::|super::)?(.+?)(;|::)', line)
            if match:
                file_path = match.group(1)
                used_module = match.group(3)

                # Convert file path to module path
                from_mod = file_path.replace('src/', '').replace('.rs', '').replace('/', '::')
                to_mod = used_module.split('::')[0]

                if from_mod and to_mod and from_mod != to_mod:
                    deps[from_mod].add(to_mod)
                    modules.add(from_mod)
                    modules.add(to_mod)
except FileNotFoundError:
    print("✓ No internal modules to check")
    sys.exit(0)

# DFS cycle detection
def has_cycle(node, visited, rec_stack, path):
    visited.add(node)
    rec_stack.add(node)
    path.append(node)

    for neighbor in deps.get(node, []):
        if neighbor not in visited:
            if has_cycle(neighbor, visited, rec_stack, path):
                return True
        elif neighbor in rec_stack:
            cycle_start = path.index(neighbor)
            print("MODULE CYCLE DETECTED:")
            print(" -> ".join(path[cycle_start:] + [neighbor]))
            return True

    rec_stack.remove(node)
    path.pop()
    return False

visited = set()
found_cycle = False
for module in modules:
    if module not in visited:
        if has_cycle(module, visited, set(), []):
            found_cycle = True
            break

if found_cycle:
    print("\n=== Rust module cycle validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No internal module cycles detected")
    print("\n=== Rust cycle validation passed ===")
EOF
```

**Thresholds:**
- **Impossible** to have crate-level cycles (Cargo prevents this)
- **Zero tolerance** for module-level cycles within a crate
- Module cycles indicate architectural issues

**Remediation:**
1. Extract shared code to separate module
2. Use trait objects for dynamic dispatch
3. Restructure module hierarchy
4. Consider splitting into multiple crates

---

### Python Cycle Detection

**Tools:** `pydeps` or custom script

**Script:** `scripts/validate-python-cycles.sh`

```bash
#!/usr/bin/env bash
# Detect circular dependencies in Python modules

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Python Dependency Cycle Detection ==="

# Find Python source directories
if [[ -f "setup.py" ]] || [[ -f "pyproject.toml" ]]; then
    SRC_DIRS=$(find . -maxdepth 2 -type d -name "*.py" -o -type d -name "src" | head -1)
    [[ -z "$SRC_DIRS" ]] && SRC_DIRS="."
else
    SRC_DIRS="."
fi

python3 <<'EOF'
import sys
import os
import ast
import re
from collections import defaultdict
from pathlib import Path

class ImportVisitor(ast.NodeVisitor):
    def __init__(self, module_path):
        self.module_path = module_path
        self.imports = []

    def visit_Import(self, node):
        for alias in node.names:
            self.imports.append(alias.name.split('.')[0])

    def visit_ImportFrom(self, node):
        if node.module and not node.level:  # Absolute import
            self.imports.append(node.module.split('.')[0])
        elif node.level:  # Relative import
            # Handle relative imports
            parts = self.module_path.split('.')
            if node.level <= len(parts):
                base = '.'.join(parts[:-node.level] if node.level > 0 else parts)
                if node.module:
                    self.imports.append(base + '.' + node.module.split('.')[0])

def find_python_files(root_dir):
    """Find all Python files in the project"""
    python_files = []
    for root, dirs, files in os.walk(root_dir):
        # Skip common non-source directories
        dirs[:] = [d for d in dirs if d not in {'.git', '.tox', '__pycache__', 'venv', '.venv', 'node_modules'}]
        for file in files:
            if file.endswith('.py'):
                python_files.append(os.path.join(root, file))
    return python_files

def get_module_path(file_path, root_dir):
    """Convert file path to module path"""
    rel_path = os.path.relpath(file_path, root_dir)
    module_path = rel_path.replace('.py', '').replace(os.sep, '.')
    if module_path.endswith('.__init__'):
        module_path = module_path[:-9]
    return module_path

def build_dependency_graph(root_dir):
    """Build dependency graph from Python files"""
    deps = defaultdict(set)
    files = find_python_files(root_dir)

    for file_path in files:
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                tree = ast.parse(f.read(), filename=file_path)

            module_path = get_module_path(file_path, root_dir)
            visitor = ImportVisitor(module_path)
            visitor.visit(tree)

            # Only track internal dependencies
            for imp in visitor.imports:
                if not imp.startswith(('_', '.')):
                    # Check if it's an internal module
                    imp_path = os.path.join(root_dir, imp.replace('.', os.sep))
                    if os.path.exists(imp_path) or os.path.exists(imp_path + '.py'):
                        deps[module_path].add(imp)
        except (SyntaxError, UnicodeDecodeError):
            continue

    return deps

def find_cycles_dfs(graph):
    """Find all cycles using DFS"""
    cycles = []
    visited = set()
    rec_stack = set()

    def dfs(node, path):
        visited.add(node)
        rec_stack.add(node)
        path.append(node)

        for neighbor in graph.get(node, []):
            if neighbor not in visited:
                dfs(neighbor, path)
            elif neighbor in rec_stack:
                # Found cycle
                cycle_start = path.index(neighbor)
                cycle = path[cycle_start:] + [neighbor]
                cycles.append(cycle)

        rec_stack.remove(node)
        path.pop()

    for node in graph:
        if node not in visited:
            dfs(node, [])

    return cycles

# Main execution
root_dir = '.'
print("Analyzing Python module dependencies...")

deps = build_dependency_graph(root_dir)

if not deps:
    print("✓ No Python modules found or no dependencies")
    sys.exit(0)

cycles = find_cycles_dfs(deps)

if cycles:
    print(f"CIRCULAR DEPENDENCIES DETECTED ({len(cycles)} cycle(s)):")
    for i, cycle in enumerate(cycles, 1):
        print(f"\nCycle {i}:")
        print("  " + " -> ".join(cycle))
    print("\n=== Python cycle validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No circular dependencies detected")
    print("\n=== Python cycle validation passed ===")
EOF
```

**Thresholds:**
- **Zero tolerance** for import cycles
- Python allows circular imports with late binding, but they indicate design issues
- Common in Django apps but should be avoided

**Remediation:**
1. Use late imports (import within function)
2. Extract shared code to common module
3. Use dependency injection
4. Restructure package hierarchy

---

## Layer Violation Detection

### Go Layer Validation

**Architecture:** Domain -> Application -> Infrastructure -> Interface

**Script:** `scripts/validate-go-layers.sh`

```bash
#!/usr/bin/env bash
# Validate Go architecture layer boundaries

set -euo pipefail

MODULE_ROOT="${1:-.}"
cd "$MODULE_ROOT" || exit 1

echo "=== Go Layer Violation Detection ==="

# Define layer hierarchy (lower number = inner layer)
declare -A LAYERS=(
    ["domain"]=1
    ["application"]=2
    ["infrastructure"]=3
    ["interface"]=4
    ["api"]=4
    ["handler"]=4
    ["controller"]=4
)

python3 <<'EOF'
import sys
import re
import subprocess
from collections import defaultdict

# Get all packages and their imports
result = subprocess.run(['go', 'list', '-f', '{{.ImportPath}}: {{join .Imports " "}}', './...'],
                       capture_output=True, text=True)

if result.returncode != 0:
    print("ERROR: Failed to list Go packages")
    sys.exit(1)

# Layer hierarchy (lower = inner)
layers = {
    'domain': 1,
    'application': 2,
    'infrastructure': 3,
    'interface': 4,
    'api': 4,
    'handler': 4,
    'controller': 4,
}

def get_layer(pkg_path):
    """Extract layer from package path"""
    for layer_name, level in layers.items():
        if f'/{layer_name}/' in pkg_path or pkg_path.endswith(f'/{layer_name}'):
            return (layer_name, level)
    return (None, 999)  # Unknown layer

violations = []
for line in result.stdout.split('\n'):
    if ':' not in line:
        continue

    pkg, imports_str = line.split(':', 1)
    pkg = pkg.strip()
    imports = imports_str.strip().split()

    pkg_layer, pkg_level = get_layer(pkg)
    if pkg_layer is None:
        continue

    for imp in imports:
        imp_layer, imp_level = get_layer(imp)
        if imp_layer is None:
            continue

        # Check if inner layer imports outer layer (violation)
        if pkg_level < imp_level:
            violations.append({
                'from': pkg,
                'from_layer': pkg_layer,
                'to': imp,
                'to_layer': imp_layer,
            })

if violations:
    print(f"LAYER VIOLATIONS DETECTED ({len(violations)} violation(s)):")
    print()
    for v in violations:
        print(f"  {v['from_layer']} -> {v['to_layer']}")
        print(f"    {v['from']}")
        print(f"    imports {v['to']}")
        print()
    print("=== Go layer validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No layer violations detected")
    print("✓ Architecture boundaries respected")
    print("\n=== Go layer validation passed ===")
EOF
```

---

### TypeScript Layer Validation

**Script:** `scripts/validate-ts-layers.sh`

```bash
#!/usr/bin/env bash
# Validate TypeScript architecture layer boundaries

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== TypeScript Layer Violation Detection ==="

find src -name "*.ts" -o -name "*.tsx" > /tmp/ts-files.txt

python3 <<'EOF'
import sys
import re
from pathlib import Path

# Layer hierarchy
layers = {
    'domain': 1,
    'core': 1,
    'application': 2,
    'infrastructure': 3,
    'adapters': 3,
    'interface': 4,
    'api': 4,
    'controllers': 4,
    'ui': 4,
}

def get_layer(file_path):
    path_parts = Path(file_path).parts
    for part in path_parts:
        if part in layers:
            return (part, layers[part])
    return (None, 999)

violations = []

with open('/tmp/ts-files.txt') as f:
    files = [line.strip() for line in f if line.strip()]

for file_path in files:
    from_layer, from_level = get_layer(file_path)
    if from_layer is None:
        continue

    try:
        with open(file_path, 'r') as f:
            content = f.read()

        # Find import statements
        imports = re.findall(r'import\s+.*\s+from\s+[\'"](.+?)[\'"]', content)

        for imp in imports:
            # Skip external modules
            if not imp.startswith('.') and not imp.startswith('/'):
                continue

            # Resolve relative path
            imp_path = str((Path(file_path).parent / imp).resolve())
            to_layer, to_level = get_layer(imp_path)

            if to_layer and from_level < to_level:
                violations.append({
                    'from': file_path,
                    'from_layer': from_layer,
                    'to': imp,
                    'to_layer': to_layer,
                })
    except Exception:
        continue

if violations:
    print(f"LAYER VIOLATIONS DETECTED ({len(violations)} violation(s)):")
    print()
    for v in violations:
        print(f"  {v['from_layer']} -> {v['to_layer']}")
        print(f"    {v['from']}")
        print(f"    imports {v['to']}")
        print()
    print("=== TypeScript layer validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No layer violations detected")
    print("\n=== TypeScript layer validation passed ===")
EOF
```

---

### Rust Layer Validation

**Script:** `scripts/validate-rust-layers.sh`

```bash
#!/usr/bin/env bash
# Validate Rust architecture layer boundaries

set -euo pipefail

CRATE_ROOT="${1:-.}"
cd "$CRATE_ROOT" || exit 1

echo "=== Rust Layer Violation Detection ==="

find src -name "*.rs" > /tmp/rust-files.txt

python3 <<'EOF'
import sys
import re
from pathlib import Path

layers = {
    'domain': 1,
    'core': 1,
    'application': 2,
    'infrastructure': 3,
    'adapters': 3,
    'interface': 4,
    'api': 4,
}

def get_layer(module_path):
    parts = module_path.split('::')
    for part in parts:
        if part in layers:
            return (part, layers[part])
    return (None, 999)

violations = []

with open('/tmp/rust-files.txt') as f:
    files = [line.strip() for line in f if line.strip()]

for file_path in files:
    # Convert file path to module path
    mod_path = file_path.replace('src/', '').replace('.rs', '').replace('/', '::')
    from_layer, from_level = get_layer(mod_path)

    if from_layer is None:
        continue

    try:
        with open(file_path, 'r') as f:
            content = f.read()

        # Find use statements
        uses = re.findall(r'use\s+crate::(.+?);', content)

        for use_stmt in uses:
            to_layer, to_level = get_layer(use_stmt)

            if to_layer and from_level < to_level:
                violations.append({
                    'from': mod_path,
                    'from_layer': from_layer,
                    'to': use_stmt,
                    'to_layer': to_layer,
                })
    except Exception:
        continue

if violations:
    print(f"LAYER VIOLATIONS DETECTED ({len(violations)} violation(s)):")
    print()
    for v in violations:
        print(f"  {v['from_layer']} -> {v['to_layer']}")
        print(f"    {v['from']}")
        print(f"    uses crate::{v['to']}")
        print()
    print("=== Rust layer validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No layer violations detected")
    print("\n=== Rust layer validation passed ===")
EOF
```

---

### Python Layer Validation

**Script:** `scripts/validate-python-layers.sh`

```bash
#!/usr/bin/env bash
# Validate Python architecture layer boundaries

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Python Layer Violation Detection ==="

find . -name "*.py" -not -path "./.venv/*" -not -path "./venv/*" > /tmp/py-files.txt

python3 <<'EOF'
import sys
import re
import ast

layers = {
    'domain': 1,
    'core': 1,
    'application': 2,
    'infrastructure': 3,
    'adapters': 3,
    'interface': 4,
    'api': 4,
    'views': 4,
}

def get_layer(path):
    parts = path.split('/')
    for part in parts:
        if part in layers:
            return (part, layers[part])
    return (None, 999)

violations = []

with open('/tmp/py-files.txt') as f:
    files = [line.strip() for line in f if line.strip()]

for file_path in files:
    from_layer, from_level = get_layer(file_path)
    if from_layer is None:
        continue

    try:
        with open(file_path, 'r') as f:
            tree = ast.parse(f.read())

        for node in ast.walk(tree):
            imports = []
            if isinstance(node, ast.Import):
                imports = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports = [node.module]

            for imp in imports:
                imp_path = imp.replace('.', '/')
                to_layer, to_level = get_layer(imp_path)

                if to_layer and from_level < to_level:
                    violations.append({
                        'from': file_path,
                        'from_layer': from_layer,
                        'to': imp,
                        'to_layer': to_layer,
                    })
    except Exception:
        continue

if violations:
    print(f"LAYER VIOLATIONS DETECTED ({len(violations)} violation(s)):")
    print()
    for v in violations:
        print(f"  {v['from_layer']} -> {v['to_layer']}")
        print(f"    {v['from']}")
        print(f"    imports {v['to']}")
        print()
    print("=== Python layer validation FAILED ===")
    sys.exit(1)
else:
    print("✓ No layer violations detected")
    print("\n=== Python layer validation passed ===")
EOF
```

---

## Complexity Metrics

### Cyclomatic Complexity

**Definition:** Number of linearly independent paths through code

**Tools by Language:**
- **Go:** `gocyclo`
- **TypeScript:** `complexity-report`, `eslint-plugin-complexity`
- **Rust:** `cargo-geiger` (unsafe analysis), custom tools
- **Python:** `radon`

#### Go Complexity Check

```bash
#!/usr/bin/env bash
# scripts/check-go-complexity.sh

go install github.com/fzipp/gocyclo/cmd/gocyclo@latest
gocyclo -over 15 . | tee /tmp/go-complexity.txt

if [[ -s /tmp/go-complexity.txt ]]; then
    echo "HIGH COMPLEXITY DETECTED"
    exit 1
fi
```

#### TypeScript Complexity Check

```bash
#!/usr/bin/env bash
# scripts/check-ts-complexity.sh

npm install -g complexity-report

cr --format plain --maxcc 15 src/**/*.ts | tee /tmp/ts-complexity.txt
```

#### Rust Complexity Check

```bash
#!/usr/bin/env bash
# scripts/check-rust-complexity.sh

# Use clippy for complexity warnings
cargo clippy -- -W clippy::cognitive_complexity
```

#### Python Complexity Check

```bash
#!/usr/bin/env bash
# scripts/check-python-complexity.sh

pip install radon
radon cc -a -nb . | tee /tmp/python-complexity.txt

# Check for high complexity
radon cc -n C . && echo "HIGH COMPLEXITY DETECTED" && exit 1
```

---

### Coupling and Cohesion

**Coupling:** Dependencies between modules
**Cohesion:** Related functionality within a module

#### Coupling Metrics

**High Coupling Indicators:**
- Module imports >10 other modules
- Module imported by >20 other modules
- Deep import chains (>5 levels)

**Detection:**

```bash
#!/usr/bin/env bash
# scripts/check-coupling.sh

# For Go
go list -f '{{.ImportPath}}: {{len .Imports}}' ./... | awk -F: '$2 > 10 {print $0}'

# For Python
find . -name "*.py" -exec grep -c "^import\|^from" {} \; | awk '$1 > 10'
```

#### Cohesion Metrics

**Low Cohesion Indicators:**
- Module with >1000 LOC
- Module with >20 public functions/classes
- Unrelated functionality in same module

---

### Acceptable Thresholds

| Metric | Acceptable | Warning | Critical |
|--------|-----------|---------|----------|
| **Cyclomatic Complexity** | 1-10 | 11-15 | >15 |
| **Function Length** | <50 LOC | 50-100 LOC | >100 LOC |
| **Module Coupling** | <5 imports | 5-10 imports | >10 imports |
| **Module Size** | <500 LOC | 500-1000 LOC | >1000 LOC |
| **Nesting Depth** | <4 levels | 4-5 levels | >5 levels |
| **Parameters** | <4 params | 4-6 params | >6 params |

**When Complexity is Acceptable:**
- Business logic with many edge cases
- State machines with many states
- Parsers with complex grammar
- Mathematical algorithms

**When Complexity is Problematic:**
- Simple CRUD operations
- Utility functions
- Configuration handling
- UI event handlers

**Remediation for High Complexity:**
1. Extract methods/functions
2. Use strategy pattern for branching logic
3. Replace conditionals with polymorphism
4. Use lookup tables instead of if/else chains
5. Simplify boolean expressions

---

## Running All Validations

**Master Script:** `scripts/validate-architecture.sh`

```bash
#!/usr/bin/env bash
# Run all architecture validations

set -euo pipefail

PROJECT_ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Architecture Validation Suite"
echo "======================================"
echo ""

FAILED=0

# Detect project type
if [[ -f "$PROJECT_ROOT/go.mod" ]]; then
    echo "==> Running Go validations..."
    bash "$SCRIPT_DIR/validate-go-cycles.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/validate-go-layers.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/check-go-complexity.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
fi

if [[ -f "$PROJECT_ROOT/package.json" ]]; then
    echo "==> Running TypeScript validations..."
    bash "$SCRIPT_DIR/validate-ts-cycles.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/validate-ts-layers.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/check-ts-complexity.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
fi

if [[ -f "$PROJECT_ROOT/Cargo.toml" ]]; then
    echo "==> Running Rust validations..."
    bash "$SCRIPT_DIR/validate-rust-cycles.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/validate-rust-layers.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/check-rust-complexity.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
fi

if [[ -f "$PROJECT_ROOT/setup.py" ]] || [[ -f "$PROJECT_ROOT/pyproject.toml" ]]; then
    echo "==> Running Python validations..."
    bash "$SCRIPT_DIR/validate-python-cycles.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/validate-python-layers.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
    bash "$SCRIPT_DIR/check-python-complexity.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
fi

# API Contract Validation
echo ""
echo "==> Running API contract validations..."
[[ -f "$PROJECT_ROOT/api/openapi.yaml" ]] && bash "$SCRIPT_DIR/validate-openapi.sh" "$PROJECT_ROOT" || true
[[ -d "$PROJECT_ROOT/proto" ]] && bash "$SCRIPT_DIR/validate-grpc-proto.sh" "$PROJECT_ROOT" || true
[[ -f "$PROJECT_ROOT/schema.graphql" ]] && bash "$SCRIPT_DIR/validate-graphql-schema.sh" "$PROJECT_ROOT" || true

# Performance Checks
echo ""
echo "==> Running performance checks..."
bash "$SCRIPT_DIR/detect-n-plus-one.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
bash "$SCRIPT_DIR/detect-unbounded-loops.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
bash "$SCRIPT_DIR/analyze-memory-patterns.sh" "$PROJECT_ROOT" || true  # Warning only

# Concurrency Checks
echo ""
echo "==> Running concurrency checks..."
bash "$SCRIPT_DIR/detect-races.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))
bash "$SCRIPT_DIR/detect-deadlocks.sh" "$PROJECT_ROOT" || true  # Warning only
bash "$SCRIPT_DIR/detect-resource-leaks.sh" "$PROJECT_ROOT" || FAILED=$((FAILED+1))

echo ""
echo "======================================"
if [[ $FAILED -eq 0 ]]; then
    echo "✓ All architecture validations passed"
    exit 0
else
    echo "✗ $FAILED validation(s) failed"
    exit 1
fi
```

---

## CI Integration

**GitHub Actions Example:**

```yaml
name: Architecture Validation
on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run architecture validations
        run: |
          chmod +x scripts/validate-architecture.sh
          scripts/validate-architecture.sh .
```

**GitLab CI Example:**

```yaml
architecture:validate:
  stage: test
  script:
    - bash scripts/validate-architecture.sh .
  only:
    - merge_requests
```

---

## API Contract Validation

### OpenAPI/Swagger Validation

**Purpose:** Ensure REST API contracts are valid, consistent, and backward-compatible

**Tools:**
- `swagger-cli` - OpenAPI validation
- `oasdiff` - Breaking change detection
- `spectral` - API linting with custom rules

**Script:** `scripts/validate-openapi.sh`

```bash
#!/usr/bin/env bash
# Validate OpenAPI/Swagger specifications

set -euo pipefail

API_SPEC="${1:-api/openapi.yaml}"
PREVIOUS_SPEC="${2:-}"

echo "=== OpenAPI Contract Validation ==="

# Check if spec exists
if [[ ! -f "$API_SPEC" ]]; then
    echo "ERROR: API spec not found: $API_SPEC"
    exit 1
fi

# Install dependencies if needed
command -v swagger-cli &> /dev/null || npm install -g @apidevtools/swagger-cli
command -v spectral &> /dev/null || npm install -g @stoplight/spectral-cli
command -v oasdiff &> /dev/null || go install github.com/tufin/oasdiff@latest

# 1. Validate syntax
echo "Validating OpenAPI syntax..."
swagger-cli validate "$API_SPEC" || {
    echo "ERROR: Invalid OpenAPI specification"
    exit 1
}
echo "✓ OpenAPI syntax valid"

# 2. Lint with Spectral
echo -e "\nLinting API specification..."
cat > /tmp/spectral-rules.yaml <<'EOF'
extends: ["spectral:oas"]
rules:
  # Require operation IDs
  operation-operationId: error
  # Require descriptions
  operation-description: warn
  info-description: error
  # Require examples
  operation-tag-defined: error
  # Versioning
  oas3-api-servers: error
  # Security
  operation-security-defined: warn
EOF

spectral lint --ruleset /tmp/spectral-rules.yaml "$API_SPEC" || {
    echo "WARNING: API linting found issues"
}

# 3. Check for breaking changes (if previous spec provided)
if [[ -n "$PREVIOUS_SPEC" ]] && [[ -f "$PREVIOUS_SPEC" ]]; then
    echo -e "\nChecking for breaking changes..."

    # Use oasdiff to detect breaking changes
    BREAKING_CHANGES=$(oasdiff breaking "$PREVIOUS_SPEC" "$API_SPEC" 2>&1 || true)

    if echo "$BREAKING_CHANGES" | grep -q "breaking changes"; then
        echo "BREAKING CHANGES DETECTED:"
        echo "$BREAKING_CHANGES"
        exit 1
    else
        echo "✓ No breaking changes detected"
    fi
fi

# 4. Custom validation checks
echo -e "\nRunning custom validation checks..."

python3 <<'EOF'
import sys
import yaml
import json
from pathlib import Path

spec_path = sys.argv[1] if len(sys.argv) > 1 else 'api/openapi.yaml'

try:
    with open(spec_path) as f:
        if spec_path.endswith('.json'):
            spec = json.load(f)
        else:
            spec = yaml.safe_load(f)
except Exception as e:
    print(f"ERROR: Failed to parse spec: {e}")
    sys.exit(1)

errors = []
warnings = []

# Check version format
if 'info' in spec and 'version' in spec['info']:
    version = spec['info']['version']
    if not version or version == '1.0.0':
        warnings.append(f"API version looks generic: {version}")

# Check for security schemes
if 'components' in spec and 'securitySchemes' not in spec.get('components', {}):
    warnings.append("No security schemes defined")

# Check all operations have tags
if 'paths' in spec:
    for path, methods in spec['paths'].items():
        for method, operation in methods.items():
            if method in ['get', 'post', 'put', 'patch', 'delete']:
                if 'tags' not in operation:
                    warnings.append(f"{method.upper()} {path} has no tags")

                # Check for request/response examples
                if method in ['post', 'put', 'patch']:
                    if 'requestBody' in operation:
                        content = operation['requestBody'].get('content', {})
                        for mime, schema in content.items():
                            if 'example' not in schema and 'examples' not in schema:
                                warnings.append(f"{method.upper()} {path} missing request example")

                # Check response codes
                if 'responses' not in operation:
                    errors.append(f"{method.upper()} {path} has no responses defined")
                else:
                    responses = operation['responses']
                    if '200' not in responses and '201' not in responses:
                        warnings.append(f"{method.upper()} {path} missing success response")

                    # Error responses
                    if method in ['post', 'put', 'patch']:
                        if '400' not in responses:
                            warnings.append(f"{method.upper()} {path} missing 400 response")

                    if '500' not in responses:
                        warnings.append(f"{method.upper()} {path} missing 500 response")

# Check for deprecated operations without sunset date
if 'paths' in spec:
    for path, methods in spec['paths'].items():
        for method, operation in methods.items():
            if operation.get('deprecated'):
                if 'x-sunset-date' not in operation:
                    warnings.append(f"{method.upper()} {path} is deprecated but has no sunset date")

# Report findings
if errors:
    print("\nERRORS:")
    for error in errors:
        print(f"  - {error}")

if warnings:
    print("\nWARNINGS:")
    for warning in warnings:
        print(f"  - {warning}")

if errors:
    print("\n=== OpenAPI validation FAILED ===")
    sys.exit(1)
else:
    print("\n✓ All custom validation checks passed")
    print("\n=== OpenAPI validation passed ===")
EOF "$API_SPEC"
```

**Thresholds:**
- **Error:** Invalid OpenAPI syntax, missing responses, breaking changes
- **Warning:** Missing examples, generic versions, incomplete documentation
- **Best Practice:** Include sunset dates for deprecated endpoints

**Remediation:**
1. Fix syntax errors with `swagger-cli validate`
2. Add comprehensive examples to all operations
3. Use semantic versioning for API versions
4. Document all error responses (400, 401, 403, 404, 500)
5. Add deprecation notices with sunset dates before removal

---

### gRPC Proto Validation

**Purpose:** Validate Protocol Buffer definitions and detect breaking changes

**Tools:**
- `buf` - Protocol Buffer linter and breaking change detector
- `protoc` - Protocol Buffer compiler

**Script:** `scripts/validate-grpc-proto.sh`

```bash
#!/usr/bin/env bash
# Validate gRPC Protocol Buffer definitions

set -euo pipefail

PROTO_DIR="${1:-proto}"

echo "=== gRPC Proto Validation ==="

# Check if proto directory exists
if [[ ! -d "$PROTO_DIR" ]]; then
    echo "ERROR: Proto directory not found: $PROTO_DIR"
    exit 1
fi

# Install buf if not present
if ! command -v buf &> /dev/null; then
    echo "Installing buf..."
    go install github.com/bufbuild/buf/cmd/buf@latest
fi

# 1. Initialize buf if not configured
if [[ ! -f "buf.yaml" ]]; then
    echo "Initializing buf configuration..."
    cat > buf.yaml <<'EOF'
version: v1
lint:
  use:
    - DEFAULT
  except:
    - PACKAGE_VERSION_SUFFIX
breaking:
  use:
    - FILE
  except:
    - EXTENSION_NO_DELETE
    - FIELD_SAME_DEFAULT
EOF
fi

# 2. Lint proto files
echo "Linting proto files..."
buf lint "$PROTO_DIR" || {
    echo "ERROR: Proto linting failed"
    exit 1
}
echo "✓ Proto files pass linting"

# 3. Build/compile protos
echo -e "\nCompiling proto files..."
buf build "$PROTO_DIR" -o /tmp/image.bin || {
    echo "ERROR: Proto compilation failed"
    exit 1
}
echo "✓ Proto files compile successfully"

# 4. Check for breaking changes (if previous version exists)
if [[ -f ".buf/previous-image.bin" ]]; then
    echo -e "\nChecking for breaking changes..."
    buf breaking "$PROTO_DIR" --against .buf/previous-image.bin || {
        echo "ERROR: Breaking changes detected"
        exit 1
    }
    echo "✓ No breaking changes detected"
fi

# Save current image for future comparison
mkdir -p .buf
cp /tmp/image.bin .buf/previous-image.bin

# 5. Custom proto validations
echo -e "\nRunning custom proto validations..."

python3 <<'EOF'
import sys
import re
from pathlib import Path
from collections import defaultdict

proto_dir = sys.argv[1] if len(sys.argv) > 1 else 'proto'
proto_files = list(Path(proto_dir).rglob('*.proto'))

if not proto_files:
    print("No proto files found")
    sys.exit(0)

errors = []
warnings = []
field_numbers = defaultdict(set)

for proto_file in proto_files:
    with open(proto_file) as f:
        content = f.read()
        lines = content.split('\n')

    # Check package declaration
    if 'package ' not in content:
        errors.append(f"{proto_file}: Missing package declaration")

    # Check for reserved field numbers
    in_message = False
    message_name = ""

    for i, line in enumerate(lines, 1):
        line = line.strip()

        # Track messages
        if line.startswith('message '):
            in_message = True
            message_name = line.split()[1].rstrip('{')

        if in_message and line == '}':
            in_message = False
            message_name = ""

        # Check field declarations
        field_match = re.match(r'^\s*(repeated\s+|optional\s+)?(\w+)\s+(\w+)\s+=\s+(\d+)', line)
        if field_match and in_message:
            field_type = field_match.group(2)
            field_name = field_match.group(3)
            field_num = int(field_match.group(4))

            # Check field number range
            if field_num > 536870911:
                errors.append(f"{proto_file}:{i}: Field number {field_num} exceeds maximum")

            # Reserved ranges
            if 19000 <= field_num <= 19999:
                errors.append(f"{proto_file}:{i}: Field number {field_num} in reserved range")

            # Track duplicates within message
            key = f"{proto_file}:{message_name}"
            if field_num in field_numbers[key]:
                errors.append(f"{proto_file}:{i}: Duplicate field number {field_num} in {message_name}")
            field_numbers[key].add(field_num)

        # Check for well-known types usage
        if 'google/protobuf/timestamp.proto' in line or 'google/protobuf/duration.proto' in line:
            # Good practice - using well-known types
            pass

        # Warn about string IDs (should use int64)
        if 'string id' in line.lower() and '=' in line:
            warnings.append(f"{proto_file}:{i}: Consider using int64 for ID fields instead of string")

        # Check for deprecated fields without comments
        if 'deprecated = true' in line:
            prev_line = lines[i-2].strip() if i > 1 else ""
            if not prev_line.startswith('//'):
                warnings.append(f"{proto_file}:{i}: Deprecated field missing explanation comment")

# Check for service definitions
service_count = 0
for proto_file in proto_files:
    with open(proto_file) as f:
        if 'service ' in f.read():
            service_count += 1

if service_count == 0:
    warnings.append("No gRPC services defined")

# Report findings
if errors:
    print("\nERRORS:")
    for error in errors:
        print(f"  - {error}")

if warnings:
    print("\nWARNINGS:")
    for warning in warnings:
        print(f"  - {warning}")

if errors:
    print("\n=== Proto validation FAILED ===")
    sys.exit(1)
else:
    print("\n✓ All proto validation checks passed")
    print("\n=== Proto validation passed ===")
EOF "$PROTO_DIR"
```

**Thresholds:**
- **Error:** Invalid proto syntax, reserved field numbers, duplicate numbers, breaking changes
- **Warning:** String IDs, missing deprecation comments, no services defined
- **Breaking Changes:** Field removal, type changes, number changes, renaming

**Remediation:**
1. Never reuse field numbers (mark as reserved instead)
2. Use int64 for IDs, not strings
3. Add comments explaining deprecated fields
4. Use well-known types (Timestamp, Duration) instead of custom types
5. Version your proto packages (e.g., `v1`, `v2`)

---

### GraphQL Schema Validation

**Purpose:** Validate GraphQL schema definitions and detect breaking changes

**Tools:**
- `graphql-inspector` - Schema validation and comparison
- `graphql-schema-linter` - Schema linting

**Script:** `scripts/validate-graphql-schema.sh`

```bash
#!/usr/bin/env bash
# Validate GraphQL schema definitions

set -euo pipefail

SCHEMA_FILE="${1:-schema.graphql}"
PREVIOUS_SCHEMA="${2:-}"

echo "=== GraphQL Schema Validation ==="

# Check if schema exists
if [[ ! -f "$SCHEMA_FILE" ]]; then
    echo "ERROR: Schema file not found: $SCHEMA_FILE"
    exit 1
fi

# Install dependencies if needed
command -v graphql-inspector &> /dev/null || npm install -g @graphql-inspector/cli
command -v graphql-schema-linter &> /dev/null || npm install -g graphql-schema-linter

# 1. Validate schema syntax
echo "Validating GraphQL schema syntax..."
graphql-inspector validate "$SCHEMA_FILE" || {
    echo "ERROR: Invalid GraphQL schema"
    exit 1
}
echo "✓ GraphQL schema syntax valid"

# 2. Lint schema
echo -e "\nLinting GraphQL schema..."
cat > /tmp/.graphql-schema-linterrc <<'EOF'
{
  "rules": {
    "types-have-descriptions": ["error", {"commentDescriptions": true}],
    "fields-have-descriptions": ["warn", {"commentDescriptions": true}],
    "enum-values-have-descriptions": "warn",
    "input-object-values-have-descriptions": "warn",
    "defined-types-are-used": "error",
    "deprecations-have-a-reason": "error",
    "types-are-capitalized": "error",
    "fields-are-camel-cased": "error"
  }
}
EOF

graphql-schema-linter --config-path /tmp/.graphql-schema-linterrc "$SCHEMA_FILE" || {
    echo "WARNING: Schema linting found issues"
}

# 3. Check for breaking changes
if [[ -n "$PREVIOUS_SCHEMA" ]] && [[ -f "$PREVIOUS_SCHEMA" ]]; then
    echo -e "\nChecking for breaking changes..."

    CHANGES=$(graphql-inspector diff "$PREVIOUS_SCHEMA" "$SCHEMA_FILE" 2>&1 || true)

    if echo "$CHANGES" | grep -q "BREAKING"; then
        echo "BREAKING CHANGES DETECTED:"
        echo "$CHANGES"
        exit 1
    else
        echo "✓ No breaking changes detected"
        if [[ -n "$CHANGES" ]]; then
            echo "Non-breaking changes:"
            echo "$CHANGES"
        fi
    fi
fi

# 4. Custom schema validations
echo -e "\nRunning custom schema validations..."

python3 <<'EOF'
import sys
import re
from pathlib import Path

schema_file = sys.argv[1] if len(sys.argv) > 1 else 'schema.graphql'

try:
    with open(schema_file) as f:
        schema = f.read()
except Exception as e:
    print(f"ERROR: Failed to read schema: {e}")
    sys.exit(1)

errors = []
warnings = []

# Check for Query type
if 'type Query' not in schema:
    errors.append("Schema must define a Query type")

# Check for pagination patterns
has_pagination = False
if 'Connection' in schema or 'Edge' in schema or 'PageInfo' in schema:
    has_pagination = True

# Check all list fields use pagination
type_blocks = re.findall(r'type\s+(\w+)\s*\{([^}]+)\}', schema)
for type_name, type_body in type_blocks:
    fields = re.findall(r'(\w+)\s*:\s*\[(\w+)\]', type_body)
    for field_name, field_type in fields:
        if not has_pagination:
            warnings.append(f"{type_name}.{field_name} returns list - consider using pagination")

# Check for deprecated fields without reason
deprecated_without_reason = re.findall(r'@deprecated\s*(?!\(reason)', schema)
if deprecated_without_reason:
    errors.append("Deprecated fields must include a reason")

# Check naming conventions
types = re.findall(r'type\s+(\w+)', schema)
for type_name in types:
    if not type_name[0].isupper():
        errors.append(f"Type '{type_name}' should be capitalized")

# Check for N+1 query risks
interfaces = re.findall(r'interface\s+(\w+)', schema)
types_implementing = re.findall(r'type\s+\w+\s+implements\s+(\w+)', schema)

# Check for proper error handling
has_error_type = 'type Error' in schema or 'interface Error' in schema
if not has_error_type:
    warnings.append("Consider defining an Error type/interface for error handling")

# Check for proper ID usage
id_fields = re.findall(r'(\w+)\s*:\s*ID[!\s]', schema)
for field in id_fields:
    if field.lower() != 'id':
        warnings.append(f"ID field '{field}' should be named 'id' for consistency")

# Check for input types
mutations = re.findall(r'type\s+Mutation\s*\{([^}]+)\}', schema)
if mutations:
    mutation_fields = mutations[0]
    # Check if mutations use input types
    if 'input ' not in schema:
        warnings.append("Mutations should use Input types for arguments")

# Check for subscriptions
if 'type Subscription' in schema:
    subscription_block = re.search(r'type\s+Subscription\s*\{([^}]+)\}', schema)
    if subscription_block:
        sub_fields = subscription_block.group(1)
        # Subscriptions should return non-null types
        nullable_subs = re.findall(r'(\w+)\s*:\s*(\w+)\s*(?!!)', sub_fields)
        for field, _ in nullable_subs:
            warnings.append(f"Subscription '{field}' should return non-null type")

# Report findings
if errors:
    print("\nERRORS:")
    for error in errors:
        print(f"  - {error}")

if warnings:
    print("\nWARNINGS:")
    for warning in warnings:
        print(f"  - {warning}")

if errors:
    print("\n=== GraphQL validation FAILED ===")
    sys.exit(1)
else:
    print("\n✓ All schema validation checks passed")
    print("\n=== GraphQL validation passed ===")
EOF "$SCHEMA_FILE"
```

**Thresholds:**
- **Error:** Invalid syntax, missing Query type, deprecated without reason, breaking changes
- **Warning:** Missing descriptions, no pagination, no error handling, nullable subscriptions
- **Breaking Changes:** Field removal, type changes, required arguments added, non-null changes

**Remediation:**
1. Always define Query type (required by spec)
2. Use Connection pattern for pagination on lists
3. Add descriptions to all types and fields
4. Include reason for all deprecated fields
5. Use Input types for mutation arguments
6. Return non-null from subscriptions

---

### Breaking Change Detection

**Purpose:** Unified detection of breaking changes across all API types

**Script:** `scripts/detect-breaking-changes.sh`

```bash
#!/usr/bin/env bash
# Unified breaking change detection

set -euo pipefail

PROJECT_ROOT="${1:-.}"
PREVIOUS_REF="${2:-origin/main}"

echo "=== API Breaking Change Detection ==="

cd "$PROJECT_ROOT" || exit 1

# Detect API types
HAS_OPENAPI=false
HAS_GRPC=false
HAS_GRAPHQL=false

[[ -f api/openapi.yaml ]] || [[ -f api/swagger.yaml ]] && HAS_OPENAPI=true
[[ -d proto ]] && HAS_GRPC=true
[[ -f schema.graphql ]] && HAS_GRAPHQL=true

if ! $HAS_OPENAPI && ! $HAS_GRPC && ! $HAS_GRAPHQL; then
    echo "No API definitions found"
    exit 0
fi

BREAKING_FOUND=false

# Check out previous version
TEMP_DIR=$(mktemp -d)
git archive "$PREVIOUS_REF" | tar -x -C "$TEMP_DIR" 2>/dev/null || {
    echo "WARNING: Could not fetch previous version from $PREVIOUS_REF"
    exit 0
}

# Check OpenAPI
if $HAS_OPENAPI; then
    echo -e "\n==> Checking OpenAPI for breaking changes..."
    CURRENT_SPEC=$(find api -name "openapi.yaml" -o -name "swagger.yaml" | head -1)
    PREVIOUS_SPEC="$TEMP_DIR/$CURRENT_SPEC"

    if [[ -f "$PREVIOUS_SPEC" ]]; then
        bash scripts/validate-openapi.sh "$CURRENT_SPEC" "$PREVIOUS_SPEC" || BREAKING_FOUND=true
    fi
fi

# Check gRPC
if $HAS_GRPC; then
    echo -e "\n==> Checking gRPC protos for breaking changes..."
    if [[ -d "$TEMP_DIR/proto" ]]; then
        # Copy previous protos to .buf for comparison
        mkdir -p .buf/previous
        cp -r "$TEMP_DIR/proto"/* .buf/previous/

        buf breaking proto --against .buf/previous || BREAKING_FOUND=true

        rm -rf .buf/previous
    fi
fi

# Check GraphQL
if $HAS_GRAPHQL; then
    echo -e "\n==> Checking GraphQL schema for breaking changes..."
    if [[ -f "$TEMP_DIR/schema.graphql" ]]; then
        bash scripts/validate-graphql-schema.sh schema.graphql "$TEMP_DIR/schema.graphql" || BREAKING_FOUND=true
    fi
fi

# Cleanup
rm -rf "$TEMP_DIR"

if $BREAKING_FOUND; then
    echo -e "\n=== BREAKING CHANGES DETECTED ==="
    echo "Review the breaking changes above and:"
    echo "  1. Fix the breaking changes, OR"
    echo "  2. Bump major version if intentional, OR"
    echo "  3. Add deprecation notices and plan migration"
    exit 1
else
    echo -e "\n=== No breaking changes detected ==="
fi
```

**Common Breaking Changes:**

| API Type | Breaking Change | Non-Breaking |
|----------|----------------|--------------|
| **REST** | Remove endpoint, rename field, change type | Add endpoint, add optional field |
| **gRPC** | Remove field, change field type, reuse number | Add field, add optional, add service |
| **GraphQL** | Remove field, add required arg, change type | Add field, add optional arg, deprecate |

**Version Bump Guidelines:**
- **Patch (1.0.x):** Bug fixes, no API changes
- **Minor (1.x.0):** New features, backward compatible
- **Major (x.0.0):** Breaking changes, requires migration

---

## Performance Checks

### N+1 Query Detection

**Purpose:** Detect inefficient database query patterns that cause performance issues

**Problem:** Loading a list then querying for each item individually
```python
# BAD: N+1 queries
users = User.all()
for user in users:
    posts = Post.where(user_id=user.id)  # Separate query per user!
```

**Solution:** Use eager loading or joins
```python
# GOOD: Single query with join
users = User.includes(:posts).all()
```

**Script:** `scripts/detect-n-plus-one.sh`

```bash
#!/usr/bin/env bash
# Detect N+1 query patterns in code

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== N+1 Query Detection ==="

python3 <<'EOF'
import sys
import re
from pathlib import Path
from collections import defaultdict

# Patterns that indicate potential N+1 queries
patterns = {
    'python': {
        'loop': r'for\s+\w+\s+in\s+(\w+)\.(?:all|filter|objects)',
        'query_in_loop': r'((?:query|filter|get|where|find)\s*\([^)]*\))',
        'orm_call': r'\.(filter|get|where|all|objects)\s*\(',
    },
    'go': {
        'loop': r'for\s+.*\s+(?:range|:=)\s+.*\.(Find|Where|Query)',
        'query_in_loop': r'\.(Find|First|Where|Query)\s*\(',
    },
    'typescript': {
        'loop': r'(?:for|\.map|\.forEach)\s*\([^)]*\)',
        'query_in_loop': r'(?:await\s+)?(?:find|findOne|findMany|query)\s*\(',
    },
    'ruby': {
        'loop': r'(?:\.each|\.map)\s+do\s+',
        'query_in_loop': r'(?:where|find|find_by|all)\s*[\(\[]',
    },
}

def detect_language(file_path):
    ext = Path(file_path).suffix
    lang_map = {
        '.py': 'python',
        '.go': 'go',
        '.ts': 'typescript',
        '.tsx': 'typescript',
        '.js': 'typescript',
        '.rb': 'ruby',
    }
    return lang_map.get(ext)

def analyze_file(file_path, lang):
    try:
        with open(file_path) as f:
            lines = f.readlines()
    except:
        return []

    issues = []
    in_loop = False
    loop_start = 0

    for i, line in enumerate(lines, 1):
        # Detect loop start
        if re.search(patterns[lang]['loop'], line):
            in_loop = True
            loop_start = i

        # Detect loop end (simplified)
        if in_loop:
            # Check for queries inside loop
            if re.search(patterns[lang]['query_in_loop'], line):
                # Check if it's a correlated query (uses loop variable)
                if re.search(r'\b\w+\.\w+\b', line):  # Simplified check
                    issues.append({
                        'file': file_path,
                        'line': i,
                        'loop_line': loop_start,
                        'code': line.strip(),
                    })

            # Simple loop end detection
            indent = len(line) - len(line.lstrip())
            if lang == 'python' and indent == 0 and line.strip():
                in_loop = False
            elif lang == 'go' and '}' in line:
                in_loop = False
            elif lang in ['typescript', 'ruby'] and '}' in line:
                in_loop = False

    return issues

# Find all code files
code_files = []
for ext in ['.py', '.go', '.ts', '.tsx', '.js', '.rb']:
    code_files.extend(Path('.').rglob(f'*{ext}'))

# Filter out common non-source directories
excluded = {'.git', 'node_modules', 'venv', '.venv', 'vendor', 'dist', 'build'}
code_files = [f for f in code_files if not any(ex in f.parts for ex in excluded)]

all_issues = []
for file_path in code_files:
    lang = detect_language(file_path)
    if lang:
        issues = analyze_file(str(file_path), lang)
        all_issues.extend(issues)

if all_issues:
    print(f"POTENTIAL N+1 QUERIES DETECTED ({len(all_issues)} issue(s)):")
    print()
    for issue in all_issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Loop at line {issue['loop_line']}")
        print(f"    Query: {issue['code']}")
        print()

    print("Remediation:")
    print("  - Use eager loading (e.g., .includes(), .with(), .populate())")
    print("  - Use joins instead of separate queries")
    print("  - Batch load with DataLoader (GraphQL)")
    print("  - Cache query results outside loop")
    print()
    print("=== N+1 detection found issues (review required) ===")
    sys.exit(1)
else:
    print("✓ No obvious N+1 query patterns detected")
    print("\n=== N+1 detection passed ===")
EOF
```

**Remediation Strategies:**

| ORM/Framework | Solution |
|---------------|----------|
| **Django** | `.select_related()` (1-to-1, FK), `.prefetch_related()` (M2M, reverse FK) |
| **SQLAlchemy** | `.joinedload()`, `.subqueryload()` |
| **ActiveRecord** | `.includes()`, `.eager_load()` |
| **Prisma** | `.include()`, `findMany()` with nested include |
| **GORM** | `.Preload()`, `.Joins()` |
| **TypeORM** | `.leftJoinAndSelect()`, eager relations |

---

### Unbounded Loop Detection

**Purpose:** Detect loops without clear termination conditions that could cause hangs

**Script:** `scripts/detect-unbounded-loops.sh`

```bash
#!/usr/bin/env bash
# Detect potentially unbounded loops

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Unbounded Loop Detection ==="

python3 <<'EOF'
import sys
import re
from pathlib import Path

def analyze_file(file_path):
    try:
        with open(file_path) as f:
            content = f.read()
            lines = content.split('\n')
    except:
        return []

    issues = []

    # Pattern 1: while True without break
    for i, line in enumerate(lines, 1):
        if re.search(r'\bwhile\s+True\s*:', line) or re.search(r'\bfor\s*\{\s*$', line):
            # Check if there's a break statement within reasonable distance
            has_break = False
            has_return = False
            check_range = min(i + 20, len(lines))

            for j in range(i, check_range):
                if 'break' in lines[j] or 'return' in lines[j]:
                    has_break = True
                    break

            if not has_break:
                issues.append({
                    'file': str(file_path),
                    'line': i,
                    'type': 'infinite_loop',
                    'code': line.strip(),
                })

        # Pattern 2: while condition without modification
        while_match = re.search(r'\bwhile\s+(\w+)', line)
        if while_match:
            var = while_match.group(1)
            # Check if variable is modified in loop
            modified = False
            check_range = min(i + 15, len(lines))

            for j in range(i+1, check_range):
                if re.search(rf'\b{var}\s*=', lines[j]) or re.search(rf'{var}\+\+', lines[j]):
                    modified = True
                    break

            if not modified and var != 'True' and var != 'true':
                issues.append({
                    'file': str(file_path),
                    'line': i,
                    'type': 'unmodified_condition',
                    'code': line.strip(),
                    'variable': var,
                })

        # Pattern 3: Recursion without base case nearby
        func_match = re.search(r'\bdef\s+(\w+)|func\s+(\w+)|function\s+(\w+)', line)
        if func_match:
            func_name = next((g for g in func_match.groups() if g), None)
            if func_name:
                # Check if function calls itself
                check_range = min(i + 30, len(lines))
                has_recursion = False
                has_base_case = False

                for j in range(i+1, check_range):
                    if func_name in lines[j] and '(' in lines[j]:
                        has_recursion = True
                    if re.search(r'\breturn\b(?!\s+\w+\()', lines[j]):
                        has_base_case = True

                if has_recursion and not has_base_case:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'recursion_no_base',
                        'code': line.strip(),
                        'function': func_name,
                    })

    return issues

# Find code files
code_files = []
for ext in ['*.py', '*.go', '*.ts', '*.tsx', '*.js', '*.rs', '*.java']:
    code_files.extend(Path('.').rglob(ext))

# Filter out common non-source directories
excluded = {'.git', 'node_modules', 'venv', '.venv', 'vendor', 'dist', 'build', 'target'}
code_files = [f for f in code_files if not any(ex in f.parts for ex in excluded)]

all_issues = []
for file_path in code_files:
    issues = analyze_file(file_path)
    all_issues.extend(issues)

if all_issues:
    print(f"POTENTIAL UNBOUNDED LOOPS DETECTED ({len(all_issues)} issue(s)):")
    print()

    for issue in all_issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Type: {issue['type']}")
        print(f"    Code: {issue['code']}")
        if 'variable' in issue:
            print(f"    Variable '{issue['variable']}' not modified in loop")
        if 'function' in issue:
            print(f"    Function '{issue['function']}' may recurse without base case")
        print()

    print("Remediation:")
    print("  - Add explicit break conditions")
    print("  - Add iteration counters with max limits")
    print("  - Ensure loop variables are modified")
    print("  - Add base cases to recursive functions")
    print("  - Consider using for loops with range instead of while")
    print()
    print("=== Unbounded loop detection found issues (review required) ===")
    sys.exit(1)
else:
    print("✓ No obvious unbounded loop patterns detected")
    print("\n=== Unbounded loop detection passed ===")
EOF
```

**Safe Loop Patterns:**

```go
// GOOD: Bounded with counter
const maxRetries = 3
for i := 0; i < maxRetries; i++ {
    if err := tryOperation(); err == nil {
        break
    }
}

// GOOD: Bounded with timeout
ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
defer cancel()
for {
    select {
    case <-ctx.Done():
        return ctx.Err()
    default:
        // work
    }
}

// GOOD: Explicit termination
for {
    item, err := queue.Pop()
    if err == ErrEmpty {
        break  // Clear exit
    }
    process(item)
}
```

---

### Memory Pattern Analysis

**Purpose:** Detect memory inefficient patterns and potential leaks

**Tools:**
- **Go:** `pprof` heap profiling
- **Rust:** `valgrind`, `heaptrack`
- **Node.js:** `heapdump`, `clinic`
- **Python:** `memory_profiler`, `tracemalloc`

**Script:** `scripts/analyze-memory-patterns.sh`

```bash
#!/usr/bin/env bash
# Analyze memory usage patterns

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Memory Pattern Analysis ==="

# Detect language
LANG=""
[[ -f "go.mod" ]] && LANG="go"
[[ -f "Cargo.toml" ]] && LANG="rust"
[[ -f "package.json" ]] && LANG="node"
[[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] && LANG="python"

if [[ -z "$LANG" ]]; then
    echo "Could not detect project language"
    exit 0
fi

case "$LANG" in
    "go")
        echo "Running Go memory analysis..."

        # Static analysis for memory issues
        python3 <<'EOF'
import sys
import re
from pathlib import Path

issues = []

for go_file in Path('.').rglob('*.go'):
    if '.git' in str(go_file) or 'vendor' in str(go_file):
        continue

    try:
        with open(go_file) as f:
            lines = f.readlines()
    except:
        continue

    for i, line in enumerate(lines, 1):
        # Detect large slice allocations
        if re.search(r'make\(\[\].*,\s*\d{6,}', line):
            issues.append({
                'file': str(go_file),
                'line': i,
                'type': 'large_allocation',
                'code': line.strip(),
            })

        # Detect append in loop (quadratic growth)
        if i > 1 and 'append(' in line:
            prev_line = lines[i-2]
            if re.search(r'\bfor\s+.*range', prev_line):
                issues.append({
                    'file': str(go_file),
                    'line': i,
                    'type': 'append_in_loop',
                    'code': line.strip(),
                })

        # Detect defer in loop (accumulates)
        if 'defer ' in line:
            # Check if in a loop
            for j in range(max(0, i-10), i):
                if re.search(r'\bfor\s+', lines[j]):
                    issues.append({
                        'file': str(go_file),
                        'line': i,
                        'type': 'defer_in_loop',
                        'code': line.strip(),
                    })
                    break

        # Detect unclosed resources
        if re.search(r'(os\.Open|http\.Get|sql\.Query)\(', line):
            # Check for defer close
            has_defer_close = False
            for j in range(i, min(i+5, len(lines))):
                if 'defer' in lines[j] and 'Close()' in lines[j]:
                    has_defer_close = True
                    break

            if not has_defer_close:
                issues.append({
                    'file': str(go_file),
                    'line': i,
                    'type': 'unclosed_resource',
                    'code': line.strip(),
                })

if issues:
    print(f"MEMORY ISSUES DETECTED ({len(issues)} issue(s)):")
    print()
    for issue in issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Type: {issue['type']}")
        print(f"    Code: {issue['code']}")
        print()
    sys.exit(1)
else:
    print("✓ No obvious memory issues detected")
EOF
        ;;

    "rust")
        echo "Running Rust memory analysis..."
        cargo clippy -- \
            -W clippy::large_stack_arrays \
            -W clippy::vec_init_then_push \
            -W clippy::useless_vec
        ;;

    "node")
        echo "Running Node.js memory analysis..."
        echo "Run: node --expose-gc --inspect app.js"
        echo "Then connect Chrome DevTools to profile memory"
        ;;

    "python")
        echo "Running Python memory analysis..."
        python3 <<'EOF'
import sys
import re
from pathlib import Path

issues = []

for py_file in Path('.').rglob('*.py'):
    if '.venv' in str(py_file) or 'venv' in str(py_file):
        continue

    try:
        with open(py_file) as f:
            content = f.read()
            lines = content.split('\n')
    except:
        continue

    for i, line in enumerate(lines, 1):
        # Global mutable defaults
        if re.search(r'def\s+\w+\([^)]*=\s*\[\]', line) or \
           re.search(r'def\s+\w+\([^)]*=\s*\{\}', line):
            issues.append({
                'file': str(py_file),
                'line': i,
                'type': 'mutable_default',
                'code': line.strip(),
            })

        # Large list comprehensions (could use generator)
        if '[' in line and 'for' in line and 'in' in line and ']' in line:
            if 'range(' in line:
                issues.append({
                    'file': str(py_file),
                    'line': i,
                    'type': 'large_listcomp',
                    'code': line.strip(),
                })

        # String concatenation in loop
        if '+=' in line and any(s in line for s in ['str', '"', "'"]):
            # Check if in loop
            for j in range(max(0, i-10), i):
                if 'for ' in lines[j] or 'while ' in lines[j]:
                    issues.append({
                        'file': str(py_file),
                        'line': i,
                        'type': 'string_concat_loop',
                        'code': line.strip(),
                    })
                    break

if issues:
    print(f"MEMORY ISSUES DETECTED ({len(issues)} issue(s)):")
    print()
    for issue in issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Type: {issue['type']}")
        print(f"    Code: {issue['code']}")
        print()

    print("Remediation:")
    print("  - Use None for mutable defaults")
    print("  - Use generators instead of list comprehensions for large datasets")
    print("  - Use ''.join() instead of string concatenation in loops")
    print()
    sys.exit(1)
else:
    print("✓ No obvious memory issues detected")
EOF
        ;;
esac

echo -e "\n=== Memory analysis complete ===)"
```

**Common Memory Issues:**

| Issue | Problem | Solution |
|-------|---------|----------|
| **Large allocations** | Single huge allocation | Stream/chunk data instead |
| **Append in loop** | Quadratic growth | Pre-allocate with capacity |
| **Defer in loop** | Defers accumulate | Extract to function or manual close |
| **Unclosed resources** | File/connection leak | Always defer close |
| **Mutable defaults** | Shared state bug | Use None, initialize in function |
| **String concat** | O(n²) copies | Use string builder/join |

---

## Concurrency Checks

### Race Detection

**Purpose:** Detect data races where multiple goroutines/threads access shared data unsafely

**Tools by Language:**
- **Go:** `go test -race`
- **Rust:** `cargo test` (Rust prevents races at compile time)
- **C/C++:** ThreadSanitizer (`-fsanitize=thread`)
- **Java:** JMH, Thread sanitizers

**Script:** `scripts/detect-races.sh`

```bash
#!/usr/bin/env bash
# Detect data races

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Race Condition Detection ==="

# Detect language
if [[ -f "go.mod" ]]; then
    echo "Running Go race detector..."

    # Run tests with race detector
    if go test -race ./... 2>&1 | tee /tmp/race-output.txt; then
        echo "✓ No data races detected"
    else
        echo "DATA RACES DETECTED:"
        cat /tmp/race-output.txt
        echo ""
        echo "Remediation:"
        echo "  - Use mutexes (sync.Mutex) to protect shared data"
        echo "  - Use channels for communication"
        echo "  - Use sync.Once for initialization"
        echo "  - Use atomic operations (sync/atomic)"
        exit 1
    fi

    # Static analysis for common race patterns
    echo -e "\nChecking for common race patterns..."
    python3 <<'EOF'
import sys
import re
from pathlib import Path

issues = []

for go_file in Path('.').rglob('*.go'):
    if any(p in str(go_file) for p in ['.git', 'vendor', '_test.go']):
        continue

    try:
        with open(go_file) as f:
            lines = f.readlines()
    except:
        continue

    in_goroutine = False
    goroutine_start = 0

    for i, line in enumerate(lines, 1):
        # Detect goroutine
        if 'go func(' in line or 'go ' in line:
            in_goroutine = True
            goroutine_start = i

        if in_goroutine:
            # Check for unprotected map access
            if re.search(r'\w+\[.*\]\s*=', line) or re.search(r'=\s*\w+\[.*\]', line):
                # Check if there's a mutex lock nearby
                has_lock = False
                for j in range(max(0, i-10), min(i+5, len(lines))):
                    if 'Lock()' in lines[j] or 'RLock()' in lines[j]:
                        has_lock = True
                        break

                if not has_lock:
                    issues.append({
                        'file': str(go_file),
                        'line': i,
                        'type': 'unprotected_map',
                        'code': line.strip(),
                    })

            # Check for shared variable access
            if re.search(r'\w+\.\w+\s*=', line):  # field assignment
                has_lock = False
                for j in range(max(0, i-10), min(i+5, len(lines))):
                    if 'Lock()' in lines[j] or 'atomic.' in lines[j]:
                        has_lock = True
                        break

                if not has_lock:
                    issues.append({
                        'file': str(go_file),
                        'line': i,
                        'type': 'unprotected_field',
                        'code': line.strip(),
                    })

            # Reset on closing brace (simplified)
            if '}' in line and not line.strip().startswith('//'):
                in_goroutine = False

if issues:
    print(f"POTENTIAL RACE CONDITIONS ({len(issues)} issue(s)):")
    print()
    for issue in issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Type: {issue['type']}")
        print(f"    Code: {issue['code']}")
        print()
    print("WARNING: These are potential issues - run 'go test -race' to confirm")
    print()
else:
    print("✓ No obvious race patterns detected (static analysis)")
EOF

elif [[ -f "Cargo.toml" ]]; then
    echo "Rust prevents data races at compile time ✓"
    echo "Running tests..."
    cargo test

elif [[ -f "CMakeLists.txt" ]] || [[ -f "Makefile" ]]; then
    echo "Running ThreadSanitizer..."
    if command -v cmake &> /dev/null; then
        mkdir -p build-tsan
        cd build-tsan
        cmake -DCMAKE_BUILD_TYPE=Debug \
              -DCMAKE_CXX_FLAGS="-fsanitize=thread -g" \
              -DCMAKE_C_FLAGS="-fsanitize=thread -g" ..
        make
        echo "Run your tests with the built binaries to detect races"
    fi
else
    echo "Language/build system not supported for race detection"
fi

echo -e "\n=== Race detection complete ==="
```

**Safe Concurrency Patterns:**

```go
// Pattern 1: Mutex protection
type SafeCounter struct {
    mu    sync.Mutex
    count int
}

func (c *SafeCounter) Inc() {
    c.mu.Lock()
    defer c.mu.Unlock()
    c.count++
}

// Pattern 2: Channel communication
func worker(jobs <-chan Job, results chan<- Result) {
    for job := range jobs {
        results <- process(job)
    }
}

// Pattern 3: Atomic operations
var counter int64
atomic.AddInt64(&counter, 1)

// Pattern 4: sync.Once for initialization
var once sync.Once
var instance *Singleton
func GetInstance() *Singleton {
    once.Do(func() {
        instance = &Singleton{}
    })
    return instance
}
```

---

### Deadlock Detection

**Purpose:** Detect potential deadlock scenarios in concurrent code

**Script:** `scripts/detect-deadlocks.sh`

```bash
#!/usr/bin/env bash
# Detect potential deadlocks

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Deadlock Detection ==="

python3 <<'EOF'
import sys
import re
from pathlib import Path
from collections import defaultdict

# Track lock acquisition order
lock_orders = defaultdict(list)
issues = []

def analyze_go_file(file_path):
    try:
        with open(file_path) as f:
            content = f.read()
            lines = content.split('\n')
    except:
        return []

    local_issues = []

    # Find functions with multiple locks
    func_pattern = r'func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)\s*\('
    lock_pattern = r'(\w+)\.(?:Lock|RLock)\(\)'

    current_func = None
    locks_in_func = []

    for i, line in enumerate(lines, 1):
        # Track function
        func_match = re.search(func_pattern, line)
        if func_match:
            if locks_in_func and len(locks_in_func) > 1:
                # Check for inconsistent order
                key = tuple(sorted(locks_in_func))
                lock_orders[key].append((str(file_path), current_func, locks_in_func))

            current_func = func_match.group(1)
            locks_in_func = []

        # Track locks
        lock_match = re.search(lock_pattern, line)
        if lock_match:
            lock_var = lock_match.group(1)
            locks_in_func.append((lock_var, i))

        # Detect nested locks (common deadlock source)
        if len(locks_in_func) >= 2:
            local_issues.append({
                'file': str(file_path),
                'line': i,
                'function': current_func,
                'type': 'multiple_locks',
                'locks': [l[0] for l in locks_in_func],
            })

        # Detect lock without unlock
        if lock_match:
            has_unlock = False
            for j in range(i, min(i+20, len(lines))):
                if 'Unlock()' in lines[j] or 'defer' in lines[j]:
                    has_unlock = True
                    break

            if not has_unlock:
                local_issues.append({
                    'file': str(file_path),
                    'line': i,
                    'type': 'missing_unlock',
                    'lock': lock_match.group(1),
                })

        # Detect channel operations while holding lock
        if any(lock in line for lock in ['.Lock()', '.RLock()']):
            for j in range(i, min(i+15, len(lines))):
                if '<-' in lines[j] and 'Unlock()' not in lines[j]:
                    local_issues.append({
                        'file': str(file_path),
                        'line': j,
                        'type': 'channel_with_lock',
                        'code': lines[j].strip(),
                    })
                    break

    return local_issues

# Find Go files
go_files = list(Path('.').rglob('*.go'))
go_files = [f for f in go_files if '.git' not in str(f) and 'vendor' not in str(f)]

all_issues = []
for go_file in go_files:
    issues = analyze_go_file(go_file)
    all_issues.extend(issues)

# Check for inconsistent lock ordering across functions
for key, occurrences in lock_orders.items():
    if len(occurrences) > 1:
        orders = [occ[2] for occ in occurrences]
        # Check if order is consistent
        if len(set(tuple(o) for o in orders)) > 1:
            all_issues.append({
                'type': 'inconsistent_lock_order',
                'locks': key,
                'occurrences': occurrences,
            })

if all_issues:
    print(f"POTENTIAL DEADLOCK RISKS ({len(all_issues)} issue(s)):")
    print()

    for issue in all_issues:
        if issue['type'] == 'multiple_locks':
            print(f"  {issue['file']}:{issue['line']}")
            print(f"    Function '{issue['function']}' acquires multiple locks:")
            print(f"    {', '.join(issue['locks'])}")
            print(f"    Ensure consistent lock ordering")

        elif issue['type'] == 'missing_unlock':
            print(f"  {issue['file']}:{issue['line']}")
            print(f"    Lock '{issue['lock']}' may not be unlocked")
            print(f"    Always use 'defer mu.Unlock()'")

        elif issue['type'] == 'channel_with_lock':
            print(f"  {issue['file']}:{issue['line']}")
            print(f"    Channel operation while holding lock:")
            print(f"    {issue['code']}")
            print(f"    Can cause deadlock if channel blocks")

        elif issue['type'] == 'inconsistent_lock_order':
            print(f"  Inconsistent lock order for: {issue['locks']}")
            for file, func, order in issue['occurrences']:
                print(f"    {file}:{func} - order: {[l[0] for l in order]}")

        print()

    print("Remediation:")
    print("  - Always acquire locks in the same order")
    print("  - Use defer to ensure unlock")
    print("  - Avoid blocking operations while holding locks")
    print("  - Consider using sync.RWMutex for read-heavy workloads")
    print("  - Use timeouts for lock acquisition")
    print()
    print("=== Deadlock detection found issues (review required) ===")
    sys.exit(1)
else:
    print("✓ No obvious deadlock patterns detected")
    print("\n=== Deadlock detection passed ===")
EOF
```

**Deadlock Prevention:**

1. **Lock Ordering:** Always acquire locks in same order
2. **Timeout:** Use `context.WithTimeout` for lock acquisition
3. **Avoid Nesting:** Minimize holding multiple locks
4. **No Blocking:** Don't block (I/O, channels) while holding lock
5. **Lock Hierarchies:** Define clear lock levels

---

### Resource Leak Detection

**Purpose:** Detect leaked resources (files, connections, goroutines, memory)

**Script:** `scripts/detect-resource-leaks.sh`

```bash
#!/usr/bin/env bash
# Detect resource leaks

set -euo pipefail

PROJECT_ROOT="${1:-.}"
cd "$PROJECT_ROOT" || exit 1

echo "=== Resource Leak Detection ==="

python3 <<'EOF'
import sys
import re
from pathlib import Path

def analyze_file(file_path, lang):
    try:
        with open(file_path) as f:
            lines = f.readlines()
    except:
        return []

    issues = []

    if lang == 'go':
        for i, line in enumerate(lines, 1):
            # File handles
            if re.search(r'(?:os\.Open|os\.Create|ioutil\.TempFile)\(', line):
                has_close = False
                for j in range(i, min(i+5, len(lines))):
                    if 'defer' in lines[j] and 'Close()' in lines[j]:
                        has_close = True
                        break
                if not has_close:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'unclosed_file',
                        'code': line.strip(),
                    })

            # HTTP connections
            if re.search(r'http\.(?:Get|Post|Do)\(', line):
                has_close = False
                for j in range(i, min(i+8, len(lines))):
                    if 'defer' in lines[j] and 'Body.Close()' in lines[j]:
                        has_close = True
                        break
                if not has_close:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'unclosed_response',
                        'code': line.strip(),
                    })

            # Goroutine leaks
            if 'go func(' in line or re.search(r'go\s+\w+\(', line):
                # Check for context cancellation
                has_context = False
                for j in range(max(0, i-5), min(i+10, len(lines))):
                    if 'context.' in lines[j] or '<-ctx.Done()' in lines[j]:
                        has_context = True
                        break
                if not has_context:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'goroutine_leak',
                        'code': line.strip(),
                    })

            # Ticker/Timer without Stop
            if re.search(r'time\.New(?:Ticker|Timer)\(', line):
                has_stop = False
                for j in range(i, min(i+10, len(lines))):
                    if '.Stop()' in lines[j]:
                        has_stop = True
                        break
                if not has_stop:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'ticker_not_stopped',
                        'code': line.strip(),
                    })

    elif lang == 'python':
        for i, line in enumerate(lines, 1):
            # File handles
            if re.search(r'open\(', line) and 'with' not in line:
                has_close = False
                for j in range(i, min(i+10, len(lines))):
                    if '.close()' in lines[j]:
                        has_close = True
                        break
                if not has_close:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'unclosed_file',
                        'code': line.strip(),
                    })

    elif lang == 'typescript':
        for i, line in enumerate(lines, 1):
            # Event listeners
            if 'addEventListener(' in line:
                has_remove = False
                for j in range(i, min(i+20, len(lines))):
                    if 'removeEventListener(' in lines[j]:
                        has_remove = True
                        break
                if not has_remove:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'listener_not_removed',
                        'code': line.strip(),
                    })

            # Subscriptions
            if '.subscribe(' in line:
                has_unsubscribe = False
                for j in range(i, min(i+15, len(lines))):
                    if 'unsubscribe()' in lines[j]:
                        has_unsubscribe = True
                        break
                if not has_unsubscribe:
                    issues.append({
                        'file': str(file_path),
                        'line': i,
                        'type': 'subscription_leak',
                        'code': line.strip(),
                    })

    return issues

# Find code files
files_to_check = []
for ext, lang in [('*.go', 'go'), ('*.py', 'python'), ('*.ts', 'typescript'), ('*.tsx', 'typescript')]:
    for f in Path('.').rglob(ext):
        if not any(ex in str(f) for ex in ['.git', 'node_modules', 'venv', 'vendor']):
            files_to_check.append((f, lang))

all_issues = []
for file_path, lang in files_to_check:
    issues = analyze_file(file_path, lang)
    all_issues.extend(issues)

if all_issues:
    print(f"POTENTIAL RESOURCE LEAKS ({len(all_issues)} issue(s)):")
    print()

    for issue in all_issues:
        print(f"  {issue['file']}:{issue['line']}")
        print(f"    Type: {issue['type']}")
        print(f"    Code: {issue['code']}")
        print()

    print("Remediation:")
    print("  - Use 'defer close()' for files and connections")
    print("  - Always close HTTP response bodies")
    print("  - Use context cancellation for goroutines")
    print("  - Stop tickers and timers when done")
    print("  - Remove event listeners on cleanup")
    print("  - Unsubscribe from observables")
    print()
    print("=== Resource leak detection found issues (review required) ===")
    sys.exit(1)
else:
    print("✓ No obvious resource leaks detected")
    print("\n=== Resource leak detection passed ===")
EOF
```

**Safe Resource Management:**

```go
// Pattern 1: Defer cleanup
func processFile(path string) error {
    f, err := os.Open(path)
    if err != nil {
        return err
    }
    defer f.Close()  // Always executes

    // process file
    return nil
}

// Pattern 2: Context for goroutines
func worker(ctx context.Context) {
    ticker := time.NewTicker(time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ctx.Done():
            return  // Clean exit
        case <-ticker.C:
            // work
        }
    }
}

// Pattern 3: HTTP response cleanup
resp, err := http.Get(url)
if err != nil {
    return err
}
defer resp.Body.Close()  // Prevent connection leak

// Pattern 4: Resource pool
db, err := sql.Open("postgres", connStr)
defer db.Close()
db.SetMaxOpenConns(25)   // Limit resources
db.SetMaxIdleConns(5)
db.SetConnMaxLifetime(5 * time.Minute)
```

---

## Summary

This validation suite provides:
- **Automated cycle detection** across 4 languages
- **Layer boundary enforcement** for clean architecture
- **Complexity analysis** with actionable thresholds
- **API contract validation** for REST, gRPC, GraphQL
- **Performance checks** for N+1 queries, loops, memory
- **Concurrency safety** for races, deadlocks, leaks
- **CI-ready scripts** for continuous validation

**Usage in Team Workflow:**
1. Architect defines layer structure and contracts
2. CI runs full validation suite on every PR
3. Violations block merge
4. Reports inform refactoring priorities
5. Performance and concurrency checks catch issues early

**Integration Points:**
- Pre-commit hooks for fast feedback
- CI/CD pipeline for comprehensive checks
- IDE integration for real-time warnings
- Code review checklists based on findings

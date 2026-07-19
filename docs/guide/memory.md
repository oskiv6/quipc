# Memory Management in Quip

## Introduction

Many low-level programming languages give developers complete freedom on how they handle memory. C is the classic example of a programming language which allows for total manual control over memory. Once you forget to free memory, you leak memory and your program will eventually run out of memory. That is why newer languages automate memory management using runtime garbage collection or reference counting, which keep track of memory usage and free it automatically at the cost of runtime performance and determinism. Other languages keep track of memory usage at compile-time using explicit lifetime annotations, like Rust. Each of these strategies has its advantages and trade-offs.

Quip takes inspiration from Rust's compile-time memory management (also known as the Borrow-Checker) and makes it significantly simpler, more intuitive, and easier to manage without sacrificing safety or zero-cost performance.

Instead of requiring explicit lifetime annotations on references (`'a`), Quip relies on three core mechanisms:
1. **Linear Liveness State Machine** — tracking exact variable lifecycles across 5 distinct states during static analysis.
2. **AST Flattening & Stack Slot Recycling** — transforming nested expressions into linear sequences to safely reuse stack memory.
3. **The Memory Obligations System** — tracking heap allocations (`@allocator`) and automatically scheduling cleanup (`@deallocator`) right at the point where a variable dies.

---

## Memory Safety Rules

Before diving into how the compiler evaluates lifetimes and obligations, we must understand the three fundamental memory safety rules enforced for every variable in Quip: **Owner**, **Copy**, and **Pin**.

### Owner

The *Owner* rule is the most restrictive rule: each value in Quip must have exactly **one sole owner** (whether on the stack or the heap). When the owner variable reaches its final use or goes out of scope, the underlying memory is either immediately recycled (stack) or freed (heap).

```quip
make func() {
    make stack = "Hello, World" // data allocated on stack and owned by `stack` variable
    
    return // eventually each stack slot is unreachable and dropped when function returns 
}
```

During program execution, the ownership of data can change. When you assign an existing variable to a new variable, ownership is **moved**, and the original variable is invalidated:

```quip
make func() {
    make stack = "Hello, World"
    make stack1 = stack // ownership transferred from `stack` to `stack1`
    // `stack` can no longer be used right now, and its stack memory index can be recycled

    make stack3 = "The Quip Programming Language"
    make stack4 = "Temporary"
    stack4 = stack3 // ownership of `stack3` transferred to `stack4` (overwriting and freeing `Temporary`)
    
    return
}
```

### Copy

To stop moving ownership and instead duplicate the underlying data, developers can tell the compiler to **copy** the value using the `!` operator at the end of an identifier or expression:

```quip
make func() {
    make stack = "Hello, World"
    make stack1 = stack ! // both variables now own independent copies of the string
    return
}
```

Note that when an expression contains compound operators, the copy is performed on the final result of the expression:

```quip
make func() {
    make stack = "Hello, World"
    make stack1 = stack + "!" // automatically copies the string before concatenation
    return
}
```

### Pin

*Pinning* (`.pin`) creates a reference pointer (`ref<T>`) to a value and guarantees that the underlying memory address will not be moved, dropped, or reallocated for as long as the pin is active.

```quip
make func() {
    make stack: Person = Person { name = "Alice" }
    make stack_p: ref<Person> = stack.pin
    
    // make stack1 = stack // Compile Error: ownership cannot be moved while active pins exist!
    test(stack_p)
    return
}
```

#### Pinning Rules & Chaining
You cannot have multiple active pins on the same variable simultaneously. You must drop or finish using the active pin before pinning the variable again:

```quip
make a: Person = Person { name = "Alice" }
make pa: ref<Person> = a.pin
// make ppa: ref<Person> = a.pin // Compile Error: 'pa' is still active!
```

If you need a reference to a reference pointer, you can chain pins sequentially from the borrowed pointer itself:

```quip
make a: Person = Person { name = "Alice" }
make pa: ref<Person> = a.pin
make ppa: ref<ref<Person>> = pa.pin // Valid: pinning the reference pointer itself
```

---

## Function Arguments & Passing Semantics

Developers have three distinct ways to pass variables across function boundaries: moving ownership, copying data, or pinning a reference.

```quip
make main() {
    make a = 10
    make b = 15
    
    // 1. Move Ownership: 'a' and 'b' are consumed and can no longer be used in main()
    make c = add_move(a, b)
    
    // 2. Copy Data: explicit copies ('!') preserve original 'a' and 'b' ownership
    make d = add_move(a !, b !)
    
    // 3. Pin Reference: passes borrowed pointers (ref<int>) without transferring ownership
    make e = add_ref(a.pin, b.pin)
}

// Taking ownership
make add_move(a: int, b: int) -> int {
    return a + b
}

// Taking pinned references
make add_ref(a: ref<int>, b: ref<int>) -> int {
    // Note: the compiler auto-dereferences ref pointers in most expressions,
    // but explicit '.deref' can be used when needed:
    return a.deref + b.deref
}

// Taking raw pointers (no ownership/pin lifecycle tracking)
make add_ptr(a: ptr<int>, b: ptr<int>) -> int {
    return 0
}
```

---

## Compiler Analysis: The Linear Liveness State Machine

During static analysis, the compiler tracks every local variable across 5 mutually exclusive liveness states:

1. **Uninitialized**: The variable is declared (`make x: int`) but not yet assigned. Attempting to read from an uninitialized variable triggers a compile-time error.
2. **Alive**: The variable owns valid data and can be freely read, modified, or moved.
3. **Moved**: Ownership of the value has been transferred to another variable or function. Any subsequent attempt to read or use this variable triggers a compile-time error pointing clearly to both the read attempt and where the value was moved.
4. **Pinned**: A borrow (`.pin`) is currently active on the variable. Moving or re-pinning the variable while in this state is strictly forbidden.
5. **Dead**: The variable has passed its final read/write operation in the source code or has gone out of scope.

### Resurrection
If a variable loses ownership and transitions to **Moved**, Quip allows you to **resurrect** it by assigning a fresh value to it later in the scope:

```quip
make a = Person { name = "Alice" }
make b = a // 'a' transitions to Moved

a = Person { name = "Bob" } // 'a' is assigned a new value and resurrected back to Alive!
```

---

## Branch-Aware Control Flow

When code branches (`if` / `elif` / `else` or `match`), Quip isolates move tracking across execution paths so mutually exclusive branches do not trigger false-positive ownership errors:

```quip
make data = get_data()

if condition {
    take_ownership(data) // 'data' moved inside 'if'
} else {
    take_ownership(data) // Valid! 'data' starts clean in 'else' from the pre-branch state
}
```

During semantic analysis, the compiler takes a snapshot of all variable liveness states right before the branching instruction. Each branch (`if` arm, `else` arm, or `match` case) evaluates independently starting from that exact snapshot:
- **Exhaustive Moves**: If a variable is moved across **all** exhaustive branches of an `if/else` or `match` statement, its merged state becomes **Moved**.
- **Conservative Retention**: If the variable remains alive on any potential execution path (for example, if an `if` statement lacks an `else` block), its post-branch state conservatively remains **Alive**.

---

## Kill Line & Stack Slot Recycling — The Twist

In traditional block-scoped languages, a local variable occupies stack memory until the closing curly brace `}` of its block. 

Quip introduces a smarter compiler optimization: **Linear Liveness Indexing**. As the compiler walks your statements, every expression and instruction increments a logical evaluation index. For each local variable, the compiler records:
- **Birth Index**: The exact instruction step where the variable is declared.
- **Last Use Index**: Updated every time the variable is read, modified, or pinned.
- **Kill Line**: The exact step immediately following its final use (`Last Use Index + 1`).

### Stack Memory Recycling
Instead of assigning a permanent, unique stack offset to every single variable declared across a function scope, the compiler **recycles stack slots**:

```quip
make x = get_large_buffer() // Birth Index: 1
process_data(x)             // Last Use Index: 2 -> Kill Line: 3 (x is now Dead)

make y = get_another_buffer() // Birth Index: 4 -> REUSES x's exact stack slot!
```

Because `x` reaches its Kill Line (`3`) before `y` is born (`4`), the compiler safely places `y` into the exact same memory slot on the stack. This keeps your program's stack memory footprint minimal and cache-friendly without requiring runtime garbage collection. *(Note: If a variable has ever been pinned via `.pin`, its stack slot is locked for the remainder of its scope to guarantee memory address stability).*

---

## Why Linear Liveness Is Possible: The Flattening System

You might wonder how a simple linear sequence can accurately track lifetimes across complex, deeply nested user expressions, compound function calls, and inner block scopes (`if` / `else` / loops).

The architectural foundation that makes linear liveness and stack slot recycling both reliable and fast is Quip’s **AST Flattening System**.

Before memory liveness analysis and stack planning execute, the compiler runs a dedicated normalization pass that performs two key transformations: **Scope Hoisting** and **Expression Decomposition**.

---

### Scope Hoisting & Scope Normalization

Whenever you declare variables inside nested blocks, conditionals, or loops (`if` / `else`, `while`, `match`), the compiler **hoists the declarations to the top level of the enclosing function**. The original `make` statements inside the nested blocks are transformed into clean **assignments**.

#### User Code:
```quip
make main() {
    make a = 10

    if true {
        make b = 10
        make c = a
    } else {
        make d = 678
    }
}
```

#### After Scope Hoisting (Compiler's Internal View):
```quip
make main() {
    make a = 10
    make b: int // Hoisted to top level as Uninitialized (internally prefixed if needed to prevent shadowing)
    make c: int // Hoisted to top level as Uninitialized
    make d: int // Hoisted to top level as Uninitialized

    if true {
        b = 10  // Transformed from 'make b = 10' into assignment -> b transitions to Alive
        c = a   // Transformed from 'make c = a' into assignment -> c transitions to Alive
    } else {
        d = 678 // Transformed from 'make d = 678' into assignment -> d transitions to Alive
    }
}
```

**Why this matters:**
By hoisting all nested declarations to the top of the function buffer, the Memory Liveness Analyzer does not need complex tree-walk algorithms or multi-layered scope lookup tables. Every variable declared anywhere in the function exists in a single, unified, flat sequence, making linear tracking (`Uninitialized` -> `Alive` -> `Dead`) simple and exact.

---

## Heap Allocations & The Obligation System

While stack memory is managed via linear liveness and slot recycling, dynamically allocated memory on the heap is tracked using **Memory Obligations**, `owned<T>` pointers, and **Type-Based Allocators/Deallocators**.

In Quip, every memory allocator and deallocator is declared as a type tagged with `@allocator` and `@deallocator`:

```quip
make type Heap {

    @pub @allocator
    make alloc (size: uint) -> !owned<any> {}

    @pub @this @deallocator
    make free () -> void {}
}
```

### How the Obligation System Works

1. **Opening an Obligation**: When the compiler encounters a call to an `@allocator` function (`Heap.alloc(...)`), it opens a **Heap Obligation** tied directly to the returned `owned<T>` variable.
2. **Compile-Time Tracking**: The obligation records:
   - When memory was allocated
   - The allocator type responsible for the memory
   - The variable currently owning the allocation
   - When the owner variable reaches its final use (its Kill Line)
3. **Explicit vs. Automatic Deallocation**:
   - **Explicit Free**: If the developer explicitly passes the `owned<T>` pointer to the appropriate `@deallocator` (`heap.free()`), the obligation is satisfied at compile time.
   - **The Auto-Release Guarantee**: If a heap-allocated `owned<T>` variable reaches its **Kill Line** without being manually freed, the compiler **automatically schedules an auto-drop call** directly into the compiled output right at the kill line.

```quip
@pure @const std: unit = @import "stdlib.quip" // import standard library that defines `heap` value

make func() {
    make data: ptr<any> = std::heap.alloc(@sizeof int) catch {
        std::io::println("Failed to allocate memory")
        return
    }
    // Heap is the most basic memory allocator
    // It requests the OS for memory and returns a pointer (`owned<any>` / `ptr<any>`)
    
    // If 'data' is not returned or manually freed, Quip's obligation system 
    // automatically frees it when 'data' reaches its kill line!
    return
}
```

### Returning Allocated Memory Across Scopes
When a function returns an `owned<T>` heap allocation or stack variable, ownership of the data is transferred out of the function scope and assigned to the caller:

```quip
make func() {
    make b = func1(5) // `b` becomes the new owner of the heap obligation/value
    return
}

make func1(a: int) -> any {
    make b = a + 1
    return b // `b` is moved out of scope safely
}
```

**Important Constraint**: You cannot return a variable if it has active pins (`.pin`) attached to it, nor can you return the raw pinned reference pointer (`ref<T>`) of a local stack variable:

```quip
make func1(a: int) -> any {
    make b = a + 1
    make b_p = b.pin
    // return b.pin // Compile Error: returning a dangling reference pointer!
    // return b     // Compile Error: cannot move ownership of a variable while active pins exist!
    return b
}
```

By combining static liveness checks, linear AST flattening, stack slot recycling, and compile-time heap obligations, Quip delivers a memory-safe, deterministic, and highly optimized programming experience right out of the box.

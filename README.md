# Quip Compiler 

> **Disclaimer** Quip is currently a Work In Progress (WIP). The language and compiler are in active development, which may result in unexpected and unstable behavior. Not intended for production use.

## About Quip

Quip is designed with versatility in mind. Whether you are a seasoned engineer or new to programming, Quip aims to provide a friendly and intuitive syntax, while still giving you the power to drop down to low-level memory management and abstract away details as needed.

This repository contains the source code for the bootstrapped Quip compiler. While it serves as the foundation for the language, the current release versions provide a precompiled, "stable" reference compiler written in C.

## Architecture
The current pipeline utilizes a custom frontend and leverages **LLVM** as the backend for code generation and optimization. The compilation process follows these stages:
- **Lexical Analysis and Parsing** - Tokenization and construction of Abstract Syntax Tree
- **Lowering** - Translating standard AST to QAST (Quip Analyzed Syntax Tree)
- **Semantic Analysis** - Checking Type correctness, memory safety and populating missing information in the QAST
- **Code generation** - Transforming the validated QAST into LLVM IR 
- **Native code generation** - Using LLVM toolchain to produce native machine code

## Key features
- **LLVM Backend** - the compiler benefits from LLVM's powerful optimization and code generation capabilities.
- **Simplified memory safety** - Quip introduces a memory management system inspired by borrow-checking, aiming to provide strict memory safety without the steep learning curve often associated with traditional borrow-checkers.

## Hello world example
```quip
@pure @const {
make std = @import "stdlib.quip"
}

@pub @entry
make main () {
    std::io::println("Hello, World!")
    return 0
}
```

## Bootstrap compiler status

Development is currently focused on stabilizing the C reference compiler's parsing phase. Once the reference implementation successfully handles complex syntax edge cases, the bootstrapped parsing pipeline will be unlocked.

- [x] Initial setup
- [x] Tokenization
- [ ] Parsing to QAST
- [ ] Semantic Analysis
- [ ] LLVM IR generation
- [ ] Native machine code generation

## Usage and Releases

The release comes with standard library files and precompiled binaries for Linux and MacOS.

> **Note** The compiler may still contain memory leaks, bugs and incomplete features

### CLI tools
- `quipc compile "path/to/file.quip"` - compiles the Quip source file to native machine code
- 'quipc build' - builds the project based on config.toml
- 'quipc init "project name"' - initializes a new Quip project

Use `quipc -h` to get more information, some options may not work yet.

### Standard Library Configuration

Currently Quip runtime library path is hardcoded as /usr/local/lib/quip/libq.o
please, compile the libq.c using your system's C compiler and install it into /usr/local/lib/quip/libq.o

The compiler expects the stdlib to be located in /usr/local/lib/quip/. Alternatively, you can specify a custom path directly in your code:

```quip 
@pure @const make std = @import "path/to/unit.quip"
```

# Building the project

Follow these three steps to bootstrap the compiler:
1. Build `build.quip` using the C reference implementation:
```
quipc compile build.quip
```
2. Run the compiled binary to generate the bootstrapper:
```
./target/a
```
3. Use the newly bootstrapped compiler:
```
./target/bootstrap/quipc
```

*Keep in mind that the bootstrapped compiler is not yet capable of running complex Quip code. For testing full language features, please continue using the C reference implementation (quipc).*

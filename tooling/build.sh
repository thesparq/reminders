#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

PINNED_ROC_VERSION="nightly-2026-09-29-7f11a82"

mkdir -p "$BUILD_DIR"

verify_toolchain() {
    echo "==> Verifying toolchain requirements..."
    if ! command -v roc &> /dev/null; then
        echo "Error: 'roc' compiler is required but not installed or not in PATH." >&2
        exit 1
    fi

    if ! command -v wasm-tools &> /dev/null; then
        echo "Error: 'wasm-tools' is required but not installed or not in PATH." >&2
        exit 1
    fi

    if ! command -v wasm-ld &> /dev/null; then
        echo "Error: 'wasm-ld' is required but not installed or not in PATH." >&2
        exit 1
    fi

    echo "==> Toolchain verified successfully."
}

build_agent() {
    local TARGET_NAME="${1:-assistant}"
    local APP_FILE="$ROOT_DIR/main.roc"
    local CORE_WASM="$BUILD_DIR/reminders_core.wasm"
    local OUTPUT_COMPONENT="$BUILD_DIR/reminders_agent.wasm"

    verify_toolchain

    echo "=============================================================="
    echo " [Phase: Build] Compiling Reminders Agent ($TARGET_NAME)"
    echo "=============================================================="

    # Step 1: Compile Roc application to WebAssembly core module
    echo "==> Compiling Roc application to WebAssembly core module ($CORE_WASM)..."
    roc build --target=wasm32 "$APP_FILE" --output="$CORE_WASM" || {
        local STATUS=$?
        if [[ ! -f "$CORE_WASM" ]]; then
            echo "Error: roc build failed with status $STATUS" >&2
            exit $STATUS
        fi
    }

    # Step 2: Componentize WASM module into Golem Component Model
    echo "==> Componentizing WASM module ($OUTPUT_COMPONENT)..."
    wasm-tools component new "$CORE_WASM" -o "$OUTPUT_COMPONENT"

    # Step 3: Validate Component Model compatibility
    echo "==> Validating Component Model compatibility..."
    wasm-tools validate "$OUTPUT_COMPONENT"

    echo "=============================================================="
    echo " Build finished successfully!"
    echo " Component: $OUTPUT_COMPONENT"
    echo " Size:      $(du -h "$OUTPUT_COMPONENT" | cut -f1)"
    echo "=============================================================="
}

COMMAND="${1:-assistant}"

case "$COMMAND" in
    assistant|app)
        build_agent "assistant"
        ;;
    check)
        verify_toolchain
        roc check "$ROOT_DIR/main.roc"
        ;;
    test)
        verify_toolchain
        roc test "$ROOT_DIR/test_suite.roc" || {
            STATUS=$?
            if [[ $STATUS -ne 1 && $STATUS -ne 2 ]]; then
                echo "Error: roc test failed with status $STATUS" >&2
                exit $STATUS
            fi
        }
        ;;
    *)
        build_agent "$COMMAND"
        ;;
esac

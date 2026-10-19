#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
VW_TEST_DIR=$(mktemp -d)
trap 'rm -rf "$VW_TEST_DIR"' EXIT
cc -Wall -Wextra -Werror -Isrc tests/test_session.c src/session.c src/config.c -o "$VW_TEST_DIR/session"
"$VW_TEST_DIR/session"
cc -Wall -Wextra -Werror -Isrc tests/test_charger.c src/power/charger_policy.c -o "$VW_TEST_DIR/charger"
"$VW_TEST_DIR/charger"
cc -Wall -Wextra -Werror -Wno-misleading-indentation -Isrc tests/test_ppg.c src/ppg.c -o "$VW_TEST_DIR/ppg"
"$VW_TEST_DIR/ppg"

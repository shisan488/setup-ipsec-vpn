#!/bin/sh
# hello_world_test.sh

testHelloWorld() {
  echo "Hello, World!"
  assertEquals "Hello, World!" "$(echo Hello, World!)"
}

# Load shunit2
. ./shunit2/shunit2
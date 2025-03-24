#!/bin/sh
# hello_world_test.sh

testHelloWorld() {
  result=$(echo "Hello, World!")
  assertEquals "Hello, World!" "$result"
}

. shunit2
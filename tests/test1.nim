import unittest

import aargs

test "bool":
  aargs:
    type
      A = ref object of RootObj
        verbose: bool

  check parseArgs("--verbose:t")[] == A(verbose: true)[]
  check parseArgs("--verbose:true")[] == A(verbose: true)[]
  check parseArgs("-v:t")[] == A(verbose: true)[]
  check parseArgs("-v:1")[] == A(verbose: true)[]
  check parseArgs("-v=1")[] == A(verbose: true)[]
  check parseArgs("-v:true")[] == A(verbose: true)[]
  check parseArgs("-v:0")[] == A(verbose: false)[]
  check parseArgs("-v:f")[] == A(verbose: false)[]

test "int":
  aargs:
    type
      A = ref object of RootObj
        i: int
  
  check parseArgs("1")[] == A(i: 1)[]
  expect ValueError:
    discard parseArgs("1.1")

test "float":
  aargs:
    type A = ref object of RootObj
      f: float
  check parseArgs("1.1")[] == A(f: 1.1)[]
  expect ValueError:
    discard parseArgs("1.1a")

test "string":
  aargs:
    type A = ref object of RootObj
      s1: string
      s2: string
  check parseArgs("111 222")[] == A(s1: "111", s2: "222")[]

test "enum":
  aargs:
    type E = enum C, D
    type
      A = ref object of RootObj
        e: E
  check parseArgs("D")[] == A(e: D)[]
  expect ValueError:
    discard parseArgs("E")

test "multi":
  aargs:
    type
      E = enum C, D
      A = ref object of RootObj
        i: int
        s: string
        e: E
        f: float
  check parseArgs("-f=1.1 -i=1 222 D")[] == A(i:1, s: "222", e: D, f:1.1)[]
  expect ValueError:
    discard parseArgs("-f=1.1 222 D -i=1")

test "default":
  aargs:
    type
      E = enum C, D
      A = ref object of RootObj
        i = 1
        s = "222"
        e = D
        f = 1.1
  check parseArgs("")[] == A(i:1, s: "222", e: D, f:1.1)[]

test "seq":
  aargs:
    type
      A = ref object of RootObj
        vv: seq[float]

  check parseArgs("1.1 2.2")[] == A(vv: @[1.1, 2.2])[]

test "cmd":
  aargs:
    type
      AAEnum = enum P, U
      R = ref object of RootObj
        v: bool
        other = ""
      A = ref object of R
      B = ref object of R
      AA = ref object of B
        e: AAEnum
        names: seq[string]
      BB = ref object of B
        name: string
        url: string
        bbV {.arg:"v".}: bool
      CC = ref object of B
        name = "d1"
        num = 11
        num2 = 0

  check parseArgs("-v b bb n1 u1 -v")[] == BB(v: true, name: "n1", url: "u1", bbV: true)[]
  check parseArgs("-v b aa -e:u n1 n2")[] == AA(v: true, e: U, names: @["n1", "n2"])[]
  check parseArgs("-v b cc")[] == CC(v: true, name: "d1", num: 11, num2: 0)[]
  check parseArgs("-v")[] == CC(v: true, name: "d1", num: 11, num2: 0)[]

  # check parseArgs("-v --num:22")[] == CC(v: true, name: "d1", num: 22, num2: 0)[]

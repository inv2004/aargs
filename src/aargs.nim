import std/parseopt
import std/macros
import std/tables
import std/strutils
import std/enumutils

template arg*(key: string) {.pragma.}

proc transform[T](x: ref object): T =
  let res = T()
  for k, v in fieldPairs(res[]):
    for kk, vv in fieldPairs(x[]):
      when k == kk:
        v = vv
        break
  res

proc levels(t: OrderedTable[string, seq[string]], n: string, lvl = 0): seq[(string, int)] =
  if n in t:
    for x in t[n]:
      result.add levels(t, x, lvl+1)
      result.add (x, lvl+1)

proc cmpKey(key, k: string, short: bool): bool =
  if short:
    key[0] == k.split("_")[^1][0]
  else:
    key == k.split("_")[^1]

proc setField(v: var bool, val: string): bool =
  v = val != "f" and (val in ["","t"] or parseBool(val))
  true

proc setField(v: var int, val: string): bool =
  v = parseInt(val)
  true

proc setField(v: var float, val: string): bool =
  v = parseFloat(val)
  true

proc setField(v: var string, val: string): bool =
  v = val
  true

proc setField[T](v: var seq[T], val: string): bool =
  var vv: T
  discard setField(vv, val)
  v.add vv
  false

proc setField(v: var enum, val: string): bool =
  v = genEnumCaseStmt(typeof(v), val, default = nil, ord(low(typeof(v))), ord(high(typeof(v))), toLowerAscii)
  true

proc setField[T](v: var T, val: string): bool =
  {.error: "setField is not defined for `" & $typeof(v) & "` type".}

proc genCase(t: string, tt: seq[string]): NimNode =
  result = nnkCaseStmt.newTree(
    newCall(bindSym "toLower", newIdentNode("a"))
  )

  for t in tt:
    result.add nnkOfBranch.newTree(
      newCall(bindSym "toLower",
        nnkPrefix.newTree(
          newIdentNode("$"),
          newCall("typeof", newIdentNode(t))
        )
      ),
      nnkStmtList.newTree(
        nnkAsgn.newTree(
          newIdentNode("res"),
          nnkCall.newTree(
            nnkBracketExpr.newTree(
              bindSym "transform",
              newIdentNode(t)
            ),
            newIdentNode("res")
          )
        )
      )
    )

  result.add nnkElse.newTree(
    quote do:
      raise newException(ValueError, "err " & `t` & ": " & a)
  )

proc genParseCmdTmpl(t: OrderedTable[string, seq[string]]): NimNode =
  let ifStmt = nnkIfStmt.newTree()

  var i = 1
  for k, v in t:
    if i == len(t):
      ifStmt.add nnkElse.newTree(genCase(k, v))
    else:
      ifStmt.add nnkElifBranch.newTree(
        nnkInfix.newTree(
          newIdentNode("of"),
          newIdentNode("res"),
          newIdentNode(k)
        ),
        genCase(k, v)
      )
    inc i

  let body = newStmtList()
  if t.len == 0:
    body.add (quote do: raise newException(ValueError, "err "))
  elif t.len == 1:
    body.add ifStmt[0]
  else:
    body.add ifStmt

  if t.len > 0:
    body.add nnkAsgn.newTree(
      newIdentNode("wasSet"),
      newIdentNode("true")
    )

  nnkStmtList.newTree(
    nnkTemplateDef.newTree(
      newIdentNode("parseCmd"),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        newEmptyNode(),
        nnkIdentDefs.newTree(
          newIdentNode("a"),
          newIdentNode("string"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          newIdentNode("res"),
          newIdentNode("untyped"),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          newIdentNode("wasSet"),
          newIdentNode("bool"),
          newEmptyNode()
        )

      ),
      newEmptyNode(),
      newEmptyNode(),
      body
    )
  )

proc genInject(k: string): NimNode =
  nnkStmtList.newTree(
    nnkLetSection.newTree(
      nnkIdentDefs.newTree(
        nnkPragmaExpr.newTree(
          newIdentNode("obj"),
          nnkPragma.newTree(
            newIdentNode("inject")
          )
        ),
        newEmptyNode(),
        if k == "": newIdentNode("a")
        else: newCall(k, newIdentNode("a"))
        # else:
        #   nnkCall.newTree(
        #     nnkBracketExpr.newTree(
        #       bindSym "transform",
        #       newIdentNode(k)
        #     ),
        #     newIdentNode("a")
        #   )
      )
    ),
    newIdentNode("body")
  )

proc genWithObjTypeTmpl(r: string, t: OrderedTable[string, seq[string]]): NimNode =
  let w = nnkIfStmt.newTree()
  for _, v in t:
    for k in v:
      w.add(
        nnkElifBranch.newTree(
          nnkInfix.newTree(
            newIdentNode("of"),
            newIdentNode("a"),
            newIdentNode(k)
          ),
          genInject(k)
        )
      )

  w.add(
    nnkElse.newTree(
      genInject("")
    )
  )

  nnkStmtList.newTree(
    nnkTemplateDef.newTree(
      newIdentNode("withObjType"),
      newEmptyNode(),
      newEmptyNode(),
      nnkFormalParams.newTree(
        newEmptyNode(),
        nnkIdentDefs.newTree(
          newIdentNode("a"),
          newIdentNode(r),
          newEmptyNode()
        ),
        nnkIdentDefs.newTree(
          newIdentNode("body"),
          newIdentNode("untyped"),
          newEmptyNode()
        )
      ),
      newEmptyNode(),
      newEmptyNode(),
      (
        if w.len == 1: w[0][0]
        else: w
      )
    )
  )

macro aargs*(body: untyped): typed =
  var rels = initOrderedTable[string, seq[string]]()

  for x in body:
    if x.kind in [nnkMethodDef, nnkTemplateDef]:
      continue
    expectKind x, nnkTypeSection
    for y in x:
      expectKind y, nnkTypeDef
      expectKind y[0], nnkIdent
      if y[2].kind == nnkEnumTy:
        continue
      expectKind y[2], nnkRefTy
      expectKind y[2][0], nnkObjectTy
      expectKind y[2][0][1], nnkOfInherit
      expectKind y[2][0][1][0], nnkIdent
      let o = strVal(y[0])
      let po = strVal(y[2][0][1][0])
      rels.mgetOrPut(po).add(o)

  var lvls = levels(rels, "RootObj").toTable()

  let root = rels["RootObj"][0]
  rels.del "RootObj"
  rels.sort(func(a, b:(string, seq[string])): int = cmp(lvls[b[0]], lvls[a[0]]))

  # echo rels
  let tParseCmd = genParseCmdTmpl(rels)
  echo tParseCmd.repr
  let tWithObjType = genWithObjTypeTmpl(root, rels)
  # echo tWithObjType.repr

  let rootId = newIdentNode(root)

  let p = quote do:
    proc parseArgs(s: string): `rootId` =
      result = `rootId`()
      var optParser = initOptParser(s)
      var processed: seq[string]
      for kind, key, val in optParser.getopt():
        var wasSet = false
        case kind
        of cmdLongOption, cmdShortOption:
          withObjType(result):
            for k, v in fieldPairs(obj[]):
              let kk =
                when v.hasCustomPragma(arg): v.getCustomPragmaVal(arg)
                else: k
              if k notin processed and cmpKey(kk, key, kind == cmdShortOption):
                wasSet = true
                if setField(v, val):
                  processed.add k
                break
          if not wasSet:
            raise newException(ValueError, "extra flag `" & key & "`")
        of cmdArgument:
          try:
            parseCmd(key, result, wasSet)
          except ValueError:
            withObjType(result):
              for k, v in fieldPairs(obj[]):
                if k notin processed:
                  wasSet = true
                  if setField(v, key):
                    processed.add k
                  break
            if not wasSet:
              raise newException(ValueError, "extra arg `" & key & "`")
        of cmdEnd:
          doAssert false

  newStmtList(
    body,
    tParseCmd,
    tWithObjType,
    p
  )

when isMainModule:
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
        upV: bool
      CC = ref object of B
        name = "d1"
        num = 11
        num2 = 0

  let x = parseArgs("-v b cc dd22 a")
  echo (CC)(x)[]

  # var x: A = B(verbose: true)
  # withObjType(x, "B"):
  #   for k, v in fieldPairs(obj[]):
  #     when typeof(v) is int:
  #       v = 300
  #     echo k, ": ", v

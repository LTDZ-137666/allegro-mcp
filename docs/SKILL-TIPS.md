# SKILL 语法与性能陷阱

这些规则全部来自在 **Allegro 25.1** 上的实测。老版本（17.4 及以前）的行为可能不同，遇到差异时请以你本机的 `axl*` 文档为准。

每条规则都附了「错 → 对」的对照，以及为什么。

---

## TL;DR

| 规则 | 错的写法 | 对的写法 |
|---|---|---|
| 批量取属性 | `car(d->nets)->name` | `d->nets~>name` |
| 遍历取值 | `nth(0 l)` `nth(1 l)` … 循环 | `foreach x l out = strcat(out x "\|")` |
| 多次取设计对象 | `axlDBGetDesign()` 到处调用 | 一次 `setq d axlDBGetDesign()` 后复用 |
| 顶层函数组合 | `sprintf(... axlCurrentDesign() axlDBGetDesignUnits())` | 拆成两次 MCP 调用 |
| 取位号 | `d->symbols~>name` | `d->symbols~>refdes` |
| 按名查对象 | SKILL 里 `foreach` 精确匹配 | SKILL 返回全表，宿主语言里过滤 |

---

## 1. `~>` 是列表级属性提取，不是单对象访问

这是最容易踩、也最花时间的一个坑。

```skill
;; 错：对单个 dbid 用 ->，在新版本上返回 nil
car(axlDBGetDesign()->nets)->name          ;; => nil
car(axlDBGetDesign()->symbols)->refdes     ;; => nil
car(axlDBGetDesign()->symbols)->bBox       ;; => nil

;; 对：对整个列表用 ~>，一次展开
axlDBGetDesign()->nets~>name               ;; => 网络名列表
axlDBGetDesign()->symbols~>refdes          ;; => ("<refdes>" ...)
```

`~>` 是 Allegro SKILL 的列表展平运算符，等价于「对列表中每个元素取该属性，然后汇总」。它对 `axlDBGetDesign()` 返回的那些列表有效，而 `->` 作用在单个元素上时可能返回 nil。

**验证方法**：先用 `length(xxx~>attr)` 确认能取到长度。如果能取到长度但 `car(...)->attr` 是 nil，就是这个问题。

> 不要用 `obj->?attr` 去探测属性是否存在——在 25.1 上它对合法属性也返回 nil，会误导判断。

---

## 2. 取值要用一次 `foreach` 遍历，不要用 `nth` 循环

`~>` 每次调用都会**重新走一遍数据库**。所以每调一次 `nth(i, list~>attr)` 就是一次全表扫描。

```skill
;; 错：每取一个元素都重新扫描，元素一多就超时
let((l axlDBGetDesign()->nets~>name)
  sprintf(nil "%L %L %L" nth(0 l) nth(1 l) nth(2 l))
)

;; 对：一次遍历，用 strcat 累积
(progn
  (setq l axlDBGetDesign()->nets~>name)
  (setq out "")
  (foreach x l out = strcat(out x "|"))
  out
)
```

实测对比（同一个设计）：

| 写法 | 结果 |
|---|---|
| `foreach` + `strcat` 一次拼完 | 全部元素，秒级返回 |
| 逐个 `nth` 取 15 个 | 超时 |
| `apply(strcat list)` | SKILL eval error（strcat 不接受单个列表参数） |

同理，`let` / `setq` 绑定 `~>` 结果后再遍历，也可能触发重复扫描。**能一次 `foreach` 拼完的，就不要分步。**

---

## 3. 一次表达式里只调一个「顶层」axl 函数

下面这些函数各自开销都很小，但**组合在同一条表达式里会超时**：

- `axlCurrentDesign()`
- `axlDBGetDesignUnits()`
- `axlDBGetDesign()`
- `axlGetAllLayers()`

```skill
;; 错：两个顶层函数放在一起，超时
sprintf(nil "%L | %L" axlCurrentDesign() axlDBGetDesignUnits())

;; 对：拆成两条表达式，在宿主语言里拼接
;; eval #1: axlCurrentDesign()
;; eval #2: axlDBGetDesignUnits()
```

但**设计对象自身的属性 + `length` 可以组合**：

```skill
;; 对：只用一次 axlDBGetDesign()，其余都是属性读取
(progn
  (setq d axlDBGetDesign())
  (sprintf nil "Nets: %d | Components: %d | Extents: %L"
    (length d->nets) (length d->symbols) d->bBox)
)
```

判断标准：**同一条表达式里出现两次「取设计根」或「取全局状态」的调用，就拆开。**

---

## 4. 语义陷阱：`~>name` 不等于位号

```skill
axlDBGetDesign()->symbols~>name      ;; => 封装名 ("<footprint>" "<footprint>" ...)
axlDBGetDesign()->symbols~>refdes    ;; => 位号   ("<refdes>" ...)
axlDBGetDesign()->symbols~>value     ;; => 元件值，未标注时可能是 nil
```

如果你要的是「U1 / R5」这种位号，用 `~>refdes`。用 `~>name` 会拿到封装名，看起来也是字符串，很容易在测试中被误认为成功。

同理：

```skill
axlDBGetDesign()->nets~>name         ;; => 网络名
axlDBGetDesign()->nets~>branches     ;; => 每个网络的 branch 列表（元素也是列表）
```

---

## 5. 按名字查单个对象：把查找搬到宿主语言

在 SKILL 里做「遍历全表、匹配一个名字、返回那个对象」看起来自然，但在这个版本上会超时：

```skill
;; 错：循环栈 + 每次取属性，元素一多就爆
(foreach n d->nets
  (when (n->name == "GND") ...)
)
```

而且 `axlDBFindByName('net "GND")` 和 `axlDbidName(dbid)` 在实测中都返回 nil（可能只对某些对象类型有效），不能当作可靠入口。

**推荐做法**：SKILL 只负责把全表拼成字符串，查找和筛选在 Python / Node / 任何宿主语言里做。

```python
# 1. 一次拿全表
names = eval_skill('(progn (setq l axlDBGetDesign()->nets~>name) (setq out "") (foreach x l out = strcat(out x "|")) out)')

# 2. 宿主语言里过滤
items = [x for x in names.split("|") if x]
if target in items:
    idx = items.index(target)
```

代价：拿不到对象级的深层属性（etch length、diff pair 等）。需要这些时，用 `allegro_eval` 直接调对应的 `axl*` 函数。

---

## 6. 哪些信息是稳定可取的

在同一环境下反复验证过、可以放心依赖的：

| 信息 | 表达式 |
|---|---|
| 设计名 | `axlCurrentDesign()` |
| 单位 | `axlDBGetDesignUnits()` |
| 版本 | `axlVersion('version)` |
| 板框范围 | `axlDBGetDesign()->bBox` |
| 网络数 | `length(axlDBGetDesign()->nets)` |
| 器件数 | `length(axlDBGetDesign()->symbols)` |
| 全部网络名 | `...->nets~>name` + `foreach` |
| 全部位号 | `...->symbols~>refdes` + `foreach` |
| 全部封装名 | `...->symbols~>name` + `foreach` |
| 全部 padstack | `...->padstacks~>name` + `foreach` |

拿不到 / 不可靠：单个对象的 `->` 属性访问、`axlDbidName`、`axlDBFindByName`。

---

## 7. 排查顺序

当某个工具在新版本 Allegro 上突然返回 nil 或报 `SKILL eval error`，按这个顺序查：

1. **报错而不是 nil** → 多半是 `strcat` / `sprintf` 收到了 nil。先确认每个参数都能独立返回非 nil。
2. **返回 nil** → 检查是不是对单对象用了 `->`，改成列表级 `~>`。
3. **超时** → 检查这条表达式里是否有：多个 `nth`、两个顶层 axl 函数、两次 `~>`、或 `foreach` 里再调 `~>`。
4. **能取长度但取不到元素** → `~>` 列表是特殊对象，避免 `sort` / `delete` 等破坏性操作（官方文档明确警告会破坏 AXL 管理的列表）。

---

## 8. 关于版本

`axl*` 的签名和行为在大版本之间会变。这套笔记基于 **25.1**。升级前后建议先跑一遍上面「稳定可取」那几条，确认没有回归，再改动上层工具代码。
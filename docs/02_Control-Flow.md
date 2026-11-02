# 2. Control Flow

Newton provides a clean, block-based approach to control flow, relying on the `end` keyword to terminate scopes.

---

## Conditional Statements

Newton provides `if`, `elif` (or `elseif`), and `else` blocks:

```crystal
fun main:
    set status: 200

    if $status == 200:
        @println "Success!"
    elif $status == 404:
        @println "Not Found"
    elif $status == 500:
        @println "Server Error"
    else:
        @println "Unknown Status"
    end
end
```

> **Note:** Newton supports both `elif` and `elseif` interchangeably.

---

## Pattern Matching

For cleaner branching, Newton offers a `match` statement using the `->` operator. This is exceptionally useful for type checking or handling specific string/integer states without writing massive `if`/`else` chains.

```crystal
fun main:
    set my_val: "Hello"

    match (typeof $my_val):
        "string" -> @println "It is a string!"
        "int"    -> @println "It is an integer!"
        "list"   -> @println "It is a list!"
        "map"    -> @println "It is a map!"
    end

    set code: 2
    match $code:
        1 -> @println "One"
        2 -> @println "Two"
        3 -> @println "Three"
    end
end
```

---

## Loops and Iteration

Newton provides three distinct ways to iterate, depending on whether you need a dynamic condition, a hardware numeric counter, or collection traversal.

### 1. The `while` Loop

Standard conditional looping. It continues until the condition evaluates to `false` (0).

```crystal
fun main:
    set count: 0

    while $count < 5:
        @println "Count: {}", $count
        count: $count + 1
    end
end
```

### 2. The `for` Loop

The `for` loop in Newton is a high-speed numeric iterator. It requires an iterator variable `&`, a start value, an end value, and a step value.

```crystal
fun main:
    ; Loops from 0 up to 10 (exclusive), stepping by 1
    for &idx, 0, 10, 1:
        @println "Current Index: {}", $idx
    end

    ; Stepping by 2
    for &step, 0, 20, 2:
        @println "Step: {}", $step
    end
end
```

### 3. The `foreach` Loop

The `foreach` loop is Newton's dedicated collection iterator. It supports both 1-variable and 2-variable modes across maps, lists, arrays, and strings. You can use either the `in` keyword or standard comma separation.

#### Iterating Over Maps (Key-Value)

```crystal
fun main:
    set user: (name: "Alice", role: "Admin", active: 1)

    ; 2-variable mode over map (key and value)
    foreach &key, &val in $user:
        @println "Key: {} | Value: {}", $key, $val
    end

    ; 1-variable mode over map (values only)
    foreach &val in $user:
        @println "Value: {}", $val
    end
end
```

#### Iterating Over Lists and Arrays

```crystal
fun main:
    set fruits: ["apple", "banana", "cherry"]

    ; 1-variable mode (element only)
    foreach &fruit in $fruits:
        @println "Fruit: {}", $fruit
    end

    ; 2-variable mode (index and element)
    foreach &idx, &fruit in $fruits:
        @println "Item {}: {}", $idx, $fruit
    end
end
```

#### Iterating Over Strings

```crystal
fun main:
    set text: "Newton"

    ; 1-variable mode (character only)
    foreach &ch in $text:
        @println "Char: {}", $ch
    end

    ; 2-variable mode (index and character)
    foreach &i, &ch in $text:
        @println "Index {}: {}", $i, $ch
    end
end
```

---

## Loop Control: `break`

To terminate a loop early, Newton provides the `break` keyword:

```crystal
fun main:
    for &i, 0, 100, 1:
        if $i == 5:
            @println "Target reached: {}, breaking out.", $i
            break
        end
    end
end
```

---

Next: [3. Functions & TCO](03_Functions.md)


# 2. Control Flow

Newton provides a clean, block-based approach to control flow, heavily relying on the `end` keyword to terminate scopes. 

## Conditional Statements

Newton uses standard `if`, `elseif`, and `else` blocks.

```asm
fun main:
    set status: 200

    if $status == 200:
        IO.println "Success!"
    elseif $status == 404:
        IO.println "Not Found"
    else:
        IO.println "Unknown Error"
    end
end
```

## Pattern Matching

For cleaner branching, Newton offers a `match` statement using the `->` operator. This is exceptionally useful for type checking or handling specific string/integer states without writing massive `if`/`else` chains. ALL cases must be handled (or which ever cases you want to handle) due to the fact that this is no 'default' keyword or 'else' for pattern matching.

```asm
fun main:
    set my_val: "Hello"

    match (typeof $my_val):
        "string" -> IO.println "It is a string!"
        "number" -> IO.println "It is a number!"
        "list"   -> IO.println "It is a list!"
    end
end
```

## Loops and Iteration

Newton provides three distinct ways to iterate, depending on whether you need a condition, a strict hardware counter, or collection traversal.

### The `while` Loop

Standard conditional looping. It continues until the condition evaluates to `false` (0).

```asm
fun main:
    set count: 0

    while $count < 5:
        IO.println $count
        count: $count + 1
    end
end
```

### The `for` Loop

The `for` loop in Newton is a highly optimized numeric iterator. It requires an address pointer (`&`) for the iterator variable, a start value, an end value, and a step value.

```asm
fun main:
    ; Loops from 0 up to (but not including) 10, stepping by 1
    for &idx, 0, 10, 1:
        @println "Current Index: {}", $idx
    end
end
```

### The `foreach` Loop

Designed specifically for iterating over collections (Maps and Arrays). It extracts both the key/index and the value using address pointers (`&`).

```asm
fun main:
    set user: (name: "Alice", role: "Admin")

    foreach &key, &value, $user:
        @println "Key: {} | Value: {}", $key, $value
    end
end
```

## Loop Control: `break`

To exit a loop early, Newton provides the `break` keyword.

> **Note:** Newton intentionally does not provide a `continue` keyword, encouraging developers to use clear conditional logic inside their loops instead.

```asm
fun main:
    for &i, 0, 100, 1:
        if $i == 5:
            @println "Target found, exiting loop."
            break
        end
    end
end
```

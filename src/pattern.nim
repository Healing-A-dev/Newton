### STRING PATTERN AND UTILITY MODULE ###
#[
Title: Pattern
Description: A simple library to add some utility functions (mainly pattern mataching) to strings.
Reason: Created for systems that do not have libpcre or systems were libpcre is not located by nim
]#



# String Reverse
proc p_reverse*(str: string): string =
    var reverse: string = ""
    var i:int = str.len - 1
    while i >= 0:
        reverse = reverse & str[i]
        i.dec()
    return reverse


# Array Join
proc p_join*(char_array: seq[char], joint: string = ""): string =
    var combined: string = ""
    for s in (0..<char_array.len):
        if s < char_array.len:
            combined = combined & char_array[s] & joint
    return combined


# Pattern Matching
proc `<?>`* (str: string, pattern: string, offset: int = 0): tuple[Result: bool, Region: seq[int], Pattern: string] {.discardable.} =
    var window: seq[char] = @[]
    var size_p: int = pattern.len
    var size_s: int = str.len
    var bottom: int = 0 + offset

    while (bottom + size_p) - 1 < str.len:
        if window.len < size_p:
            window.add(str[bottom..(size_p + bottom) - 1])
        if window.len == size_p and window.p_join() == pattern:
            return (Result: true, Region: @[bottom, (size_p + bottom) - 1], Pattern: window.p_join())
        elif window.len == size_p and window.p_join() != pattern:
           window = @[]
          
        bottom = bottom + 1
        
    return (Result: false, Region: @[-1], Pattern: "")


# Global Replace
proc p_replace*(str: string, to_replace: string, amount: int = 1): string =
    var char_array: seq[char] = @[]
    var match_count: int = 0

    if to_replace.len > 1:
        var region: seq[int] = (str <?> to_replace).Region
        if (str <?> to_replace).Result:
            for i in 0..<str.len:
                if i < region[0] or i > region[1]:
                    char_array.add(str[i])
    else:
        for s in 0..<str.len:
            var character = str[s]
            if "" & character != to_replace or match_count >= amount:
                char_array.add(character)
            else:
                match_count.inc()

    if char_array.len > 0:
        return char_array.p_join()
    else:
        return str

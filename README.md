#  Nutq Darwin

majority is a mess...
## Known Bugs
- macOS
    - command s + command z should probably close the start menu.
        - undo/redo is pretty bad in general
    - because i attribute based on line indices instead of start/end/repeat (which was hard to get to work), copy paste doesn't work on eventful lines (neither tabs nor events are copied over)
        - related: copy pasting sometimes doesn't make sense in that the first line may still have old start, tedious to work around
    - focus state acquisition is terrible, switching out and in of textview causes delay
- iOS
    - strikethrough doesn't go away when it should
    - text wrapping isnt ideal

- general
    - multi line highlights can be behind times or buttons

// SPDX-License-Identifier: 0BSD
//
// The error catalogue. It is data: each message has an
// id, a plain explanation and an example that would work, so messages can be
// translated later by replacing this table and nothing else. A message must make
// sense read aloud by a screen reader, so the title and the explanation never
// hold a bare bracket: they say "closing square bracket". Only the example, which
// is code, may. `{a}`, `{b}`, `{c}` and `{d}` stand for the four words a diagnostic
// carries (a name, what was found, what was expected, a line of the sketch fixed).
//
// Every id has at least one sketch in tests/errors/<id>/ with the message it must
// produce, and a test fails when one is missing.
package lang

import "core:strings"

Severity :: enum u8 {
	Error,
	Warning,
	Hint,
}

Message_Id :: enum u8 {
	// What the lexer found
	Unknown_Character,
	Unterminated_Text,
	Bad_Escape,
	Bad_Number,
	Bad_Colour,
	Colour_At_Statement_Start,
	// Brackets
	Missing_Close_Square,
	Missing_Close_Round,
	Missing_Close_Curly,
	Extra_Close,
	Needs_Brackets,
	Deep_Nesting,
	Missing_Comma,
	List_Comma,
	Mixed_Braces,
	// Habits from other languages
	Comma_In_Call,
	Call_Parentheses,
	Equals_In_Condition,
	Sign_Instead_Of_Minus,
	To_Instead_Of_Learn,
	// Words
	Capital_Word,
	Unknown_Word,
	Ambiguous_Word,
	// Statements
	Statement_Start,
	Unexpected_Token,
	Nothing_After_Equals,
	Else_Without_If,
	Give_Outside_Learn,
	Stop_Outside_Learn,
	Missing_Block,
	For_Missing_Word,
	Every_Missing_Unit,
	Use_Needs_Text,
	Unknown_Event,
	Learn_Missing_Name,
	Learn_Reserved_Name,
	Learn_Repeated_Parameter,
	Learn_Default_Not_One_Item,
	// What the checker found (step 3)
	Unknown_Name,
	No_Value_Yet,
	Kind_Conflict,
	Constant_Changed,
	Reserved_Name,
	Case_Only_Difference,
	Value_Of_Nothing,
	Wrong_Argument_Count,
	Wrong_Argument_Kind,
	Missing_Required_Word,
	Word_Twice,
	Operator_Types,
	Condition_Not_Boolean,
	Wrong_Kind_Here,
	Bad_Field,
	Unknown_Field,
	It_Outside_Block,
	Wrong_Item_Kind,
	Block_Gives_Wrong_Kind,
	Changed_While_Walking,
	Give_Missing_On_Path,
	Give_Kinds_Differ,
	Constant_Changed_By_Verb,
	Result_Dropped,
	Shared_Change,
	Name_Hides,
	Labels_Needed,
}

Entry :: struct {
	severity: Severity,
	title:    string,
	explain:  string,
	label:    string, // what the example is: "Did you mean:", "For example:"
	example:  string, // code; empty means there is nothing to show
}

CATALOGUE := [Message_Id]Entry{
	.Unknown_Character = {.Error, "I don't know this character",
		"`{a}` is not part of the language. Words are made of letters, numbers of digits, and a hash starts a comment.",
		"Without it:", "{b}"},
	.Unterminated_Text = {.Error, "This text never closes",
		"Text starts and ends with a double quote, and it has to end on the same line.",
		"Write:", "{b}"},
	.Bad_Escape = {.Error, "I don't know the escape `{a}`",
		"Inside text a backslash starts an escape. I know a quote (backslash and a quote), a backslash (two of them), a new line (backslash n) and a tab (backslash t).",
		"To write the backslash itself:", "{b}"},
	.Bad_Number = {.Error, "`{a}` is not a number I can read",
		"A number is digits with an optional fraction, like 10 or 0.5. Write the zero before the point, and leave out exponents and underscores.",
		"Write:", "{b}"},
	.Bad_Colour = {.Error, "`{a}` has the wrong number of digits for a colour",
		"A colour written with a hash has 3, 4, 6 or 8 hex digits: red, green and blue, and transparency last.",
		"Write:", "{b}"},
	.Colour_At_Statement_Start = {.Error, "A line cannot start with a colour",
		"`{a}` is read as a colour, but a line has to start with a word. If you meant a comment, leave a space after the hash.",
		"Did you mean:", "{b}"},

	.Missing_Close_Square = {.Error, "This block is never closed",
		"The opening square bracket here has no closing one. {a}",
		"Write:", "{b}"},
	.Missing_Close_Round = {.Error, "This round bracket is never closed",
		"The opening round bracket here has no closing one. Round brackets make a group read as one thing, so each needs its closing bracket.",
		"Write:", "{b}"},
	.Missing_Close_Curly = {.Error, "This curly bracket is never closed",
		"The opening curly bracket here has no closing one. A vector or a record ends with a closing curly bracket.",
		"Write:", "{b}"},
	.Extra_Close = {.Error, "This closing {a} bracket has no opening one",
		"Nothing is open here, so there is nothing to close. {b}",
		"Without it:", "{c}"},
	.Needs_Brackets = {.Error, "This value needs brackets",
		"`{a}` works out a value, so when it sits inside another call, wrap it in round brackets so it reads as one thing. Or let `roci fmt` add them for you.",
		"Write:", "{b}"},
	.Deep_Nesting = {.Hint, "Three brackets deep is hard to read",
		"Give the inner value a name on the line above, and use the name here.",
		"Write:", "{b}"},
	.Missing_Comma = {.Error, "Items in curly brackets are separated by commas",
		"Between the items of a vector or a record goes a comma.",
		"Write:", "{b}"},
	.List_Comma = {.Error, "Lists have no commas",
		"The items of a list are written with spaces between them. Commas belong to vectors and records, which use curly brackets.",
		"Write:", "{b}"},
	.Mixed_Braces = {.Error, "A vector or a record, not both",
		"Curly brackets with names, like x: 1, make a record. Curly brackets without names make a vector. One pair cannot be both.",
		"As a vector:", "{b}"},

	.Comma_In_Call = {.Error, "Arguments are not separated by commas",
		"Write the arguments one after another with spaces. Commas are only for vectors and records.",
		"Write:", "{b}"},
	.Call_Parentheses = {.Error, "A verb is not called with round brackets",
		"A verb is followed by its arguments, with no brackets and no commas. Round brackets are for grouping a value that needs working out.",
		"Write:", "{a}"},
	.Equals_In_Condition = {.Error, "A condition asks, it does not assign",
		"A single equals sign gives a name a value. To ask whether two things are the same, write `is`.",
		"Write:", "{a}"},
	.Sign_Instead_Of_Minus = {.Error, "Two values side by side",
		"`{a}` follows a value with nothing between them. If you meant to subtract, put a space after the minus sign.",
		"Write:", "{b}"},
	.To_Instead_Of_Learn = {.Error, "Teach a new word with learn",
		"rocinante does not use `to` for teaching a verb. Teach one with `learn`, then the new word, then what it takes.",
		"Write:", "{b}"},

	.Capital_Word = {.Error, "rocinante's words are written in lowercase",
		"`{a}` is written with capitals. Did you mean `{b}`?",
		"Did you mean:", "{c}"},
	.Unknown_Word = {.Error, "I don't know the word `{a}`",
		"A line starts with a verb, a keyword or a name, and I don't know `{a}`. Check the spelling, or teach the word with `learn`.",
		"{c}", "{b}"},
	.Ambiguous_Word = {.Warning, "`{a}` could be read two ways",
		"Here `{a}` is read as a connecting word. If you meant the value called `{a}`, put it in round brackets.",
		"To mean the value:", "{b}"},

	.Statement_Start = {.Error, "A line has to start with a word",
		"`{a}` cannot start a line. A line starts with a verb, a keyword or a name.",
		"Without it:", "{b}"},
	.Unexpected_Token = {.Error, "I did not expect this here",
		"A line holds one statement, and `{a}` comes after a complete one. Put it on its own line, or inside a one-line block separate statements with two spaces.",
		"On two lines:", "{b}"},
	.Nothing_After_Equals = {.Error, "Nothing after the equals sign",
		"An equals sign gives a name a value, so a value has to follow it.",
		"For example:", "{a} = 10"},
	.Else_Without_If = {.Error, "An else needs an if before it",
		"An `else` continues an `if`: it goes right after the closing square bracket of the if's block.",
		"After an if:", "{b}"},
	.Give_Outside_Learn = {.Error, "give only works inside a verb you teach",
		"`give` hands a value back from a verb taught with `learn`. Outside one there is nothing to hand it back to.",
		"Inside a verb of your own:", "{b}"},
	.Stop_Outside_Learn = {.Error, "stop only works inside a verb you teach",
		"`stop` ends a verb taught with `learn` early. Outside one there is nothing to end.",
		"Inside a verb of your own:", "{b}"},
	.Missing_Block = {.Error, "`{a}` needs a block",
		"After `{a}` comes a block in square brackets: everything inside it belongs to the `{a}`.",
		"With a block:", "{b}"},
	.For_Missing_Word = {.Error, "This for is missing `{a}`",
		"A counting loop reads `for i from 1 to 10`, and a loop over a list reads `for each p in particles`.",
		"Write:", "{b}"},
	.Every_Missing_Unit = {.Error, "every needs seconds or frames",
		"Say what to count: `every 2 seconds`, or `every 10 frames`.",
		"Write:", "{b}"},
	.Use_Needs_Text = {.Error, "use needs a name in quotes",
		"Write the name of the library as text.",
		"Write:", "{b}"},
	.Unknown_Event = {.Error, "I don't know the event `{a}`",
		"`on` runs a block when something happens. The events I know are {b}.",
		"Did you mean:", "{c}"},

	.Learn_Missing_Name = {.Error, "learn needs a name",
		"After `learn` comes the new word, then the names of what it takes.",
		"Write:", "{b}"},
	.Learn_Reserved_Name = {.Error, "`{a}` is already a word",
		"The language already uses `{a}`, so it cannot be taught or used as a name here. Pick another one.",
		"Write:", "{b}"},
	.Learn_Repeated_Parameter = {.Error, "`{a}` appears twice",
		"Each thing a verb takes needs its own name.",
		"Write:", "{b}"},
	.Learn_Default_Not_One_Item = {.Error, "A default is one value",
		"After `with`, each optional word is followed by exactly one value, like `points 5`. Put anything bigger in round brackets.",
		"Write:", "{b}"},

	.Unknown_Name = {.Error, "I don't know the name `{a}`",
		"`{a}` is not a name you have given a value, and it is not a verb or a built-in value either. {b}",
		"{c}", "{d}"},
	.No_Value_Yet = {.Error, "`{a}` has no value yet",
		"`{a}` is given its value further down the sketch, but this line runs first, so it has nothing to use. Give it a value above this line.",
		"Write:", "{d}"},
	.Kind_Conflict = {.Error, "`{a}` keeps one kind of value",
		"`{a}` holds {b}, but here it is given {c}. A name keeps one kind of value; use a new name for {c}.",
		"Write:", "{d}"},
	.Constant_Changed = {.Error, "`{a}` is a constant",
		"`{a}` is written in capitals, so it is a constant: it is given a value once and can never change. If it has to change, write it in lowercase.",
		"Write:", "{d}"},
	.Reserved_Name = {.Error, "`{a}` is already a word",
		"The language already uses `{a}` for something else, so it cannot be the name of a value. Pick another name.",
		"Write:", "{d}"},
	.Case_Only_Difference = {.Warning, "`{a}` and `{b}` differ only in capitals",
		"They are two different names, which is almost always a typo. If you meant the same one, spell it the same way.",
		"Write:", "{d}"},
	.Value_Of_Nothing = {.Error, "`{a}` does not give a value back",
		"`{a}` draws or changes something, but it has nothing to hand back, so it cannot be used as a value. Use it on a line of its own.",
		"Write:", "{d}"},
	.Wrong_Argument_Count = {.Error, "`{a}` takes {b}",
		"This line gives `{a}` {c}.",
		"For example:", "{d}"},
	.Wrong_Argument_Kind = {.Error, "`{a}` needs {b}",
		"Here it is given {c}.",
		"Write:", "{d}"},
	.Missing_Required_Word = {.Error, "`{a}` needs `{b}`",
		"`{a}` is not complete without its `{b}` part.",
		"Write:", "{d}"},
	.Word_Twice = {.Error, "`{b}` is used twice",
		"A call takes each connecting word once. The second `{b}` is not needed.",
		"Write:", "{d}"},
	.Operator_Types = {.Error, "I cannot work this out",
		"`{a}` does not work with {b} and {c}. Numbers go with numbers, vectors with vectors of the same size or with a number, and text joins with anything using plus.",
		"Write:", "{d}"},
	.Condition_Not_Boolean = {.Error, "A condition has to be true or false",
		"`{a}` asks a question, so what follows it has to be a comparison like `x > 10`, or a name that holds true or false. Here it is {b}.",
		"Write:", "{d}"},
	.Wrong_Kind_Here = {.Error, "`{a}` needs {b} here",
		"Here it is given {c}.",
		"Write:", "{d}"},
	.Bad_Field = {.Error, "`{a}` is not a part of {b}",
		"{c}",
		"Write:", "{d}"},
	.Unknown_Field = {.Error, "No record like this has `{a}`",
		"This is {b}. It has no field called `{a}`, and no line of the sketch gives it one. {c}",
		"Did you mean:", "{d}"},
	.It_Outside_Block = {.Error, "`{a}` only works inside a list verb",
		"`{a}` stands for the current item (or the running value) inside the block of keep, skip, collect, find, sort or combine. It has no meaning anywhere else.",
		"For example:", "{d}"},
	.Wrong_Item_Kind = {.Error, "`{a}` needs the same kind of item as the list",
		"The list holds {b}, but this line gives `{a}` {c}. A list holds one kind of item.",
		"Write:", "{d}"},
	.Block_Gives_Wrong_Kind = {.Error, "The block of `{a}` has to give {b}",
		"Here it gives {c}.",
		"Write:", "{d}"},
	.Give_Missing_On_Path = {.Error, "`{a}` does not always give a value back",
		"`{a}` gives a value on some paths, but {b}. A verb that gives has to give on every path, so add a `give` there too.",
		"Write:", "{d}"},
	.Give_Kinds_Differ = {.Error, "`{a}` gives two kinds of value",
		"An earlier `give` in `{a}` hands back {b}, but this one hands back {c}. A verb gives one kind of value, and several results come back as a record.",
		"Write:", "{d}"},
	.Constant_Changed_By_Verb = {.Error, "`{b}` changes what `{a}` holds",
		"`{a}` is written in capitals, so it is a constant and can never change, but `{b}` changes the list or record it is given. Give it a copy instead.",
		"Write:", "{d}"},
	.Result_Dropped = {.Warning, "`{a}` gives a value back, and nothing uses it",
		"This line calls `{a}` and throws its result away, which is usually a mistake. Keep the value in a name.",
		"Write:", "{d}"},
	.Shared_Change = {.Hint, "`{a}` and `{b}` are the same value",
		"`{a}` and `{b}` are one list or record, so changing it through `{a}` changes it through `{b}` too. If you wanted a separate one, copy it where it is made.",
		"Write:", "{d}"},
	.Name_Hides = {.Warning, "`{a}` hides a name of the sketch",
		"`{a}` is also a name you give a value to at the top of the sketch. In here, `{a}` means this one, and the other cannot be reached. A different name avoids mixing the two up.",
		"Write:", "{d}"},
	.Labels_Needed = {.Error, "`{a}` is written with labels",
		"Shapes are written with {b} in front of their values, so a number is never mistaken for another and the line reads as what it draws.",
		"Write:", "{d}"},
	.Changed_While_Walking = {.Error, "`{a}` changes while the loop walks it",
		"A `for each` is going through `{a}` right now, and adding to it, taking from it or giving it a new value in the middle makes the walk lose its place. Walk a copy, then change the list.",
		"Write:", "{d}"},
}

// Replaces `{a}`, `{b}` and `{c}` in a template. Anything else, braces included,
// stays as it is. The caller frees the result.
fill_template :: proc(template: string, args: [4]string, allocator := context.allocator) -> string {
	b := strings.builder_make(0, len(template) + 16, allocator)
	for i := 0; i < len(template); i += 1 {
		if template[i] == '{' && i + 2 < len(template) && template[i + 2] == '}' {
			switch template[i + 1] {
			case 'a': strings.write_string(&b, args[0]); i += 2; continue
			case 'b': strings.write_string(&b, args[1]); i += 2; continue
			case 'c': strings.write_string(&b, args[2]); i += 2; continue
			case 'd': strings.write_string(&b, args[3]); i += 2; continue
			}
		}
		strings.write_byte(&b, template[i])
	}
	return strings.to_string(b)
}

Diagnostic :: struct {
	id:   Message_Id,
	span: Span,
	args: [4]string,
}

severity_of :: proc(d: Diagnostic) -> Severity {
	return CATALOGUE[d.id].severity
}

// Whether any diagnostic is an error: warnings and hints do not stop a sketch.
has_errors :: proc(diagnostics: []Diagnostic) -> bool {
	for d in diagnostics {
		if severity_of(d) == .Error {
			return true
		}
	}
	return false
}

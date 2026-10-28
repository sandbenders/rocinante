// SPDX-License-Identifier: 0BSD
package lang

Token_Kind :: enum u8 {
	End_Of_File,
	Newline,
	Number,        // 10, 0.5
	Text,          // "hello"; the raw source, quotes included (see unescape)
	Colour,        // #ff8800
	Name,          // a word: a verb, a keyword, a variable. The parser decides which.
	Open_Square,   // [
	Close_Square,  // ]
	Open_Round,    // (
	Close_Round,   // )
	Open_Curly,    // {
	Close_Curly,   // }
	Comma,
	Colon,
	Dot,
	Equals,        // =
	Plus,
	Minus,         // subtraction
	Minus_Prefix,  // -10: a space before (or nothing that could be subtracted from) and none after
	Star,
	Slash,
	Percent,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
	Invalid,       // a character the language has no use for, or a literal that is malformed
}

Token :: struct {
	kind:   Token_Kind,
	span:   Span,
	// How many spaces or tabs came before it on its line. For the first token of a
	// line that is the indentation, which the parser reads only to explain bracket
	// mistakes; two or more inside a one-line block end a call.
	spaces: int,
}

// What is wrong with a literal or a character. The parser turns each into a
// message of the catalogue.
Lex_Problem_Kind :: enum u8 {
	Unknown_Character,
	Unterminated_Text,
	Bad_Escape,
	Bad_Number,
	Bad_Colour,
}

Lex_Problem :: struct {
	kind: Lex_Problem_Kind,
	span: Span,
}

// A `#` comment, kept apart from the tokens so `roci fmt` can put it back.
Comment :: struct {
	span:     Span, // from the `#` to the end of the line
	own_line: bool, // nothing but spaces before it on its line
}

Lexed :: struct {
	tokens:   []Token, // always ends with End_Of_File
	comments: []Comment,
	problems: []Lex_Problem,
}

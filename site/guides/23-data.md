---
title: "Data files"
summary: "Read JSON, CSV, TSV, TOML and text files with load, write them with save, and split text into lines."
weight: 23
---

Many sketches start from data: a list of birds, a table of scores, a poem. Put the file in the sketch's `assets/data` folder (`roci add birds.json` does it) and `load` it by name:

```roci
// assets/data/birds.json:
//   { "title": "Birds", "birds": [ { "name": "owl", "size": 26 } { ... } ] }
birds = load "birds.json"
heading = birds.title
for each b in birds.birds [ print b.name ]
```

What `load` gives has the shape of the file. A JSON object is a record whose members are its fields, a JSON list is a list, and numbers, text and true or false are what they say. The checker reads the file while it checks the sketch, so `birds.birds` is known before the sketch runs, and a field the file does not have is a mistake it tells you about, with the fields it does have.

## Tables

A CSV or TSV file is a list of records, one for each line after the first. The first line names the columns, and each name becomes a field (`First Name` is `first_name`). A column of numbers holds numbers, any other holds text:

```roci
// assets/data/scores.csv:  Name,Points
//                          Ana,42
rows = load "scores.csv"
total = 0
for each r in rows [ total = total + r.points ]
```

## Text

A text file is one text, and `lines` splits it into its lines:

```roci
poem = load "poem.txt"
y = 40
for each verse in lines poem [
  print verse
]
```

TOML works as JSON does, with the keys before any heading as fields and each `[table]` a record of its own.

## Spreadsheets and documents

Excel (`.xlsx`) and OpenDocument spreadsheets (`.ods`) load as tables, as a CSV does: the first row names the columns and the rest are records. A workbook has several sheets, and `sheet` picks one by name (the first if it is left out):

```roci
stock = load "stock.xlsx"
notes = load "stock.xlsx" sheet "Notes"
```

What a cell shows is what you get: a number, a text, or for a formula the result it last had. A date comes as the number Excel keeps it as. A document (`.odt`) loads as its text, a paragraph to a line, so `lines (load "letter.odt")` is its paragraphs. rocinante reads these files and does not write them: `save` a CSV, which a spreadsheet opens.

## Saving

`save` with a value first writes it to a file, in the kind its name ends in:

```roci
scores = [ { name: "Ana", points: 10 } { name: "Bo", points: 12 } ]
save scores "scores.json"
save scores "scores.csv"
```

The files go to the sketch's `output` folder, as pictures do. A list of records is a table in a CSV, with the names of the fields on the first line; a vector is a list of its numbers and a color is text such as `#ff0000ff`. A `.txt` file is written from a text, or from a list of texts, one on each line, and a `.toml` file from a record.

To keep a value for the next run of the sketch, `remember` is simpler: it needs no file name and writes where it should. Use `save` for files meant to leave the sketch, such as a spreadsheet to open elsewhere.

## What is in a folder

`files in "images"` is the list of the names of the files in a folder of the assets, in order:

```roci
for each name in files in "images" [ print name ]
```

`examples/data` reads three files and draws them, and saves a small summary when S is pressed.

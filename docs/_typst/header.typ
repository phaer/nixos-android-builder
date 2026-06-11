// Tables: prevent overflow, enable word wrap
#set table(
  stroke: 0.5pt + luma(180),
  inset: 6pt,
)

// Definition lists: add spacing between items
#show terms.item: it => {
  v(1.5em)
  line(length: 100%, stroke: 0.3pt + luma(200))
  v(0.5em)
  it
}

// Code blocks: smaller font, prevent overflow
#show raw.where(block: true): set text(size: 8pt)
#show raw.where(block: false): set text(size: 9pt)

// Table cells: allow word wrap
#show table.cell: set par(justify: false)
#show table.cell: set text(size: 9pt)

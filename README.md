# rstar
R* Tree implementation in Lua
## Description
A [R* Tree](https://infolab.usc.edu/csci599/Fall2001/paper/rstar-tree.pdf) (pronounced r star tree) is a data structure which is meant to store n-dimensional boxes, in a way that makes queries, like range searches, very efficient.
This is a variant of the [R-Tree](http://www-db.deis.unibo.it/courses/SI-LS/papers/Gut84.pdf): the key difference is that R* Tree optimizes its structure over time. As items are inserted or deleted, this tree will get more robust and nodes will overlap less.
This implementation in particular works with *2D AABBs (Axis-Aligned Bounding-Boxes)*.

### What's this good for?
  :heavy_check_mark: Represent infinite worlds, as this structure has no fixed boundaries
  
  :heavy_check_mark: Storing mostly static objects: the trade off for quality of the structure, is insertion and deletion speed (which can be tuned)
  
  :heavy_check_mark: Drawing applications: selection of shapes is vary fast (with single clicks and selection areas as well)
  
  :heavy_check_mark: Game developement: store obstacles with a wide range of sizes to detect collisions and speed up raycasting

## How to use
At the top of your main script, require [rstar.lua](rstar.lua) as follows:

```lua
rstar = require "rstar"
```
## Class reference

#### rstar.new(settings)

Creates a new instance of R* Tree, using a table of `settings` as argument.
Here's the list of `settings`' valid fields:
* `M` the maximum number of children per node; must be a integer number >= 4. The default value is 20.
* `m` the minimum number of children per node; must be a integer number >= 2 and <= M/2. The default value is 8 (40% of M).
* `reinsert_p` the number of children to reinsert when their quantity exeeds M; must be a integer number >= 1 and < M. The default value is 6 (30% of M).
* `reinsert_method` the method used to decide which `reinsert_p` children should be reinserted; `'weighted'` uses the medium point of all children, and `'normal'` uses the node's center instead. The default value is `'normal'`.
* `choice_p` the number of leaf nodes to check when choosing where to locate a new entry; must be a integer number >= 1 and <= M. The default value is M. You should worry about this parameter when your M value is big.

Returns the new tree.

#### rstar:insert(box)

Inserts `box` in the tree. The argument must be a table in this form:
```lua
  box = {
    x = 15, y = 10,
    w = 30, h = 25,
  }
```
Where x and y are the position of the box, and w and h are width and height.

Returns a numeric id, which can be used to delete the box from the tree.

#### rstar:delete(id)

Deletes a previously inserted box in the tree: remember to store the id you got from `insert`.

Returns the box, or nil if id was not found.

#### rstar:search(s, result)

Collects all boxes which intersect with the search box `s` (which should respect the structure showed in `insert`), and inserts them in the table result.
Note: the function does not clear the table.

Returns nothing.

#### rstar:select(p, result)

Collects all boxes which contain the point `p`, and inserts them in the table result.
`p` should look like this:
```lua
  p = {
    x = 20, 
    y = 15,
  }
```
Note: the function does not clear the table.

Returns nothing.

#### rstar:draw([only_boxes])

This method will work only if the script runs in [LOVE2D](https://love2d.org/) framework v.0.7.0 and higher.
This is a debug method: draws tree's structure (for now only if its height is <= 5). Each level is drawn with a different color, while boxes are drawn in white.
When `only_boxes` is set to false, this method won't draw internal nodes.

Returns nothing.

## Planned features
- Bulk loading
- Nearest-neighbor search
- Circular area range-search
